-- =========================================================
-- FS25 Fertilizer Depot - Storage & Transaction System
-- =========================================================

---@class DepotSystem
DepotSystem = {}
local DepotSystem_mt = Class(DepotSystem)

function DepotSystem.new(pricing)
    local self = setmetatable({}, DepotSystem_mt)
    self._pricing   = pricing
    self._depots    = {}   -- [depotId] = depot state table
    self._nextId    = 1
    return self
end

-- ─── Depot Registration ──────────────────────────────────

function DepotSystem:registerDepot()
    local id = self._nextId
    self._nextId = self._nextId + 1
    self._depots[id] = {
        id            = id,
        storageLevel  = {},  -- [fillTypeName] = liters
        vehiclesNearby = {},
    }
    return id
end

function DepotSystem:unregisterDepot(depotId)
    self._depots[depotId] = nil
end

function DepotSystem:getDepot(depotId)
    return self._depots[depotId]
end

-- ─── Storage Helpers ─────────────────────────────────────

function DepotSystem:getStorageLevel(depotId, fillTypeName)
    local depot = self._depots[depotId]
    if not depot then return 0 end
    return depot.storageLevel[fillTypeName] or 0
end

function DepotSystem:setStorageLevel(depotId, fillTypeName, liters)
    local depot = self._depots[depotId]
    if not depot then return end
    local clamped = math.max(0, math.min(DepotConstants.STORAGE_CAPACITY, liters))
    depot.storageLevel[fillTypeName] = clamped
end

-- Returns table: {[fillTypeName] = {current, capacity}} for all known fill types.
function DepotSystem:getStorageInfo(depotId)
    local depot = self._depots[depotId]
    if not depot then return {} end
    local info = {}
    local fillTypes = g_DepotManager and g_DepotManager.sfBridge:getFillTypeList() or {}
    for _, ft in ipairs(fillTypes) do
        info[ft.name] = {
            current  = depot.storageLevel[ft.name] or 0,
            capacity = DepotConstants.STORAGE_CAPACITY,
        }
    end
    return info
end

-- ─── Vehicle Tracking ────────────────────────────────────

function DepotSystem:addVehicleNearby(depotId, vehicle)
    local depot = self._depots[depotId]
    if not depot then return end
    depot.vehiclesNearby[vehicle] = true
end

function DepotSystem:removeVehicleNearby(depotId, vehicle)
    local depot = self._depots[depotId]
    if not depot then return end
    depot.vehiclesNearby[vehicle] = nil
end

-- Returns the first vehicle in range with a compatible fill unit, or nil.
function DepotSystem:findCompatibleVehicle(depotId, fillTypeIndex)
    local depot = self._depots[depotId]
    if not depot then return nil, nil end
    for vehicle, _ in pairs(depot.vehiclesNearby) do
        if vehicle and vehicle.getFillUnits then
            local units = vehicle:getFillUnits()
            if units then
                for unitIndex, unit in ipairs(units) do
                    if vehicle:fillUnitSupportsFillType(unitIndex, fillTypeIndex) then
                        return vehicle, unitIndex
                    end
                end
            end
        end
    end
    return nil, nil
end

-- ─── Buy Transaction ─────────────────────────────────────
-- Returns: success (bool), message key (string), actualLiters (number)
function DepotSystem:buyFillType(depotId, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if not g_server then return false, "fd_error_server", 0 end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot", 0 end

    -- Clamp to purchase limits
    local liters = math.max(DepotConstants.MIN_PURCHASE_LITERS,
                   math.min(DepotConstants.MAX_PURCHASE_LITERS, requestedLiters))

    -- Find compatible vehicle and fill unit
    local vehicle, unitIndex = self:findCompatibleVehicle(depotId, fillTypeIndex)
    if not vehicle then return false, "fd_depot_no_trailer", 0 end

    -- Check available space in fill unit
    local freeCapacity = vehicle:getFillUnitFreeCapacity(unitIndex)
    if freeCapacity <= 0 then return false, "fd_depot_tank_full", 0 end
    liters = math.min(liters, freeCapacity)

    -- Calculate cost
    local cost = self._pricing:calculateBuyCost(fillTypeName, liters)

    -- Check farm balance
    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if not farm then return false, "fd_error_farm", 0 end
    if farm.balance < cost then return false, "fd_depot_no_money", 0 end

    -- Draw from depot storage first, remainder is fresh supply
    local fromStorage = math.min(liters, depot.storageLevel[fillTypeName] or 0)
    if fromStorage > 0 then
        depot.storageLevel[fillTypeName] = (depot.storageLevel[fillTypeName] or 0) - fromStorage
    end

    -- Deduct money
    g_currentMission:addMoney(-cost, farmId, MoneyType.PURCHASE_SEEDS, true, true)

    -- Fill the vehicle
    vehicle:addFillUnitFillLevel(farmId, unitIndex, liters, fillTypeIndex,
                                 ToolType.UNDEFINED, nil)

    return true, "fd_depot_buy_success", liters
end

-- ─── Sell Transaction ────────────────────────────────────
-- Drains fillTypeName from the nearest compatible vehicle into depot storage.
-- Returns: success (bool), message key (string), liters sold (number), revenue (number)
function DepotSystem:sellFillType(depotId, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if not g_server then return false, "fd_error_server", 0, 0 end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot", 0, 0 end

    local vehicle, unitIndex = self:findCompatibleVehicle(depotId, fillTypeIndex)
    if not vehicle then return false, "fd_depot_no_trailer", 0, 0 end

    local available = vehicle:getFillUnitFillLevel(unitIndex)
    if available <= 0 then return false, "fd_depot_tank_empty", 0, 0 end

    local liters = math.min(requestedLiters or available, available)

    -- Check depot storage space
    local currentStored = depot.storageLevel[fillTypeName] or 0
    local space = DepotConstants.STORAGE_CAPACITY - currentStored
    liters = math.min(liters, math.max(0, space))
    if liters <= 0 then return false, "fd_depot_storage_full", 0, 0 end

    -- Calculate revenue
    local revenue = self._pricing:calculateSellRevenue(fillTypeName, liters)

    -- Drain vehicle
    vehicle:addFillUnitFillLevel(farmId, unitIndex, -liters, fillTypeIndex,
                                 ToolType.UNDEFINED, nil)

    -- Store in depot
    depot.storageLevel[fillTypeName] = currentStored + liters

    -- Pay farm
    g_currentMission:addMoney(revenue, farmId, MoneyType.HARVEST_INCOME, true, true)

    return true, "fd_depot_sell_success", liters, revenue
end

-- ─── Save / Load ─────────────────────────────────────────

function DepotSystem:saveToXML(xmlFile, depotId, basePath)
    local depot = self._depots[depotId]
    if not depot then return end
    local i = 0
    for name, liters in pairs(depot.storageLevel) do
        if liters and liters > 0 then
            local path = basePath .. ".fill(" .. i .. ")"
            xmlFile:setString(path .. "#type", name)
            xmlFile:setFloat(path  .. "#liters", liters)
            i = i + 1
        end
    end
end

function DepotSystem:loadFromXML(xmlFile, depotId, basePath)
    local depot = self._depots[depotId]
    if not depot then return end
    local i = 0
    while true do
        local path = basePath .. ".fill(" .. i .. ")"
        local name = xmlFile:getString(path .. "#type")
        if not name then break end
        local liters = xmlFile:getFloat(path .. "#liters", 0)
        depot.storageLevel[name] = math.max(0, math.min(DepotConstants.STORAGE_CAPACITY, liters))
        i = i + 1
    end
end
