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
        id           = id,
        storageLevel = {},  -- [fillTypeName] = liters
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
    local cap = (g_DepotManager and g_DepotManager.settings.storageCapacity)
                or DepotConstants.STORAGE_CAPACITY
    local clamped = math.max(0, math.min(cap, liters))
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

-- ─── Vehicle Search ──────────────────────────────────────

local VEHICLE_SEARCH_RADIUS_SQ = 60 * 60  -- 60-metre radius

local function collectVehiclesRecursive(v, list)
    table.insert(list, v)
    local ok, impls = pcall(function() return v:getAttachedImplements() end)
    if ok and impls then
        for _, impl in ipairs(impls) do
            if impl.object then
                collectVehiclesRecursive(impl.object, list)
            end
        end
    end
end

-- Finds a compatible vehicle+fillUnit near a world position (px, pz).
-- forSell=true  → unit currently HAS the fill type loaded.
-- forSell=false → unit can ACCEPT the fill type and has free capacity.
local function findVehicleNearPosition(px, pz, fillTypeIndex, forSell)
    if not g_currentMission then return nil, nil end

    for _, vehicle in pairs(g_currentMission.vehicles or {}) do
        if vehicle and vehicle.rootNode then
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            local dx, dz = vx - px, vz - pz
            if dx * dx + dz * dz <= VEHICLE_SEARCH_RADIUS_SQ then
                local targets = {}
                collectVehiclesRecursive(vehicle, targets)
                for _, veh in ipairs(targets) do
                    local spec = veh.spec_fillUnit
                    if spec and spec.fillUnits then
                        for fuIdx, fillUnit in ipairs(spec.fillUnits) do
                            if forSell then
                                if fillUnit.fillType == fillTypeIndex and (fillUnit.fillLevel or 0) > 0 then
                                    return veh, fuIdx
                                end
                            else
                                if veh.fillUnitSupportsFillType and veh:fillUnitSupportsFillType(fuIdx, fillTypeIndex) then
                                    local free = veh:getFillUnitFreeCapacity(fuIdx) or 0
                                    if free > 0 then return veh, fuIdx end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Public wrapper using the depot's root node as search origin.
function DepotSystem:findCompatibleVehicle(depotId, fillTypeIndex, forSell)
    local placeable = g_DepotManager and g_DepotManager.depots[depotId]
    if not placeable or not placeable.rootNode then return nil, nil end
    local px, _, pz = getWorldTranslation(placeable.rootNode)
    return findVehicleNearPosition(px, pz, fillTypeIndex, forSell)
end

-- ─── Buy Transaction (from Depot dialog, vehicle must be near DEPOT) ─────
-- Returns: success (bool), message key (string), actualLiters (number)
function DepotSystem:buyFillType(depotId, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if not g_server then return false, "fd_error_server", 0 end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot", 0 end

    local liters = math.max(DepotConstants.MIN_PURCHASE_LITERS,
                   math.min(DepotConstants.MAX_PURCHASE_LITERS, requestedLiters))

    local vehicle, unitIndex = self:findCompatibleVehicle(depotId, fillTypeIndex, false)
    if not vehicle then return false, "fd_depot_no_trailer", 0 end

    local freeCapacity = vehicle:getFillUnitFreeCapacity(unitIndex)
    if freeCapacity <= 0 then return false, "fd_depot_tank_full", 0 end
    liters = math.min(liters, freeCapacity)

    local cost = self._pricing:calculateBuyCost(fillTypeName, liters)

    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if not farm then return false, "fd_error_farm", 0 end
    if farm.balance < cost then return false, "fd_depot_no_money", 0 end

    local fromStorage = math.min(liters, depot.storageLevel[fillTypeName] or 0)
    if fromStorage > 0 then
        depot.storageLevel[fillTypeName] = (depot.storageLevel[fillTypeName] or 0) - fromStorage
    end

    g_currentMission:addMoney(-cost, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)
    vehicle:addFillUnitFillLevel(farmId, unitIndex, liters, fillTypeIndex,
                                 ToolType.UNDEFINED, nil)

    return true, "fd_depot_buy_success", liters
end

-- ─── Silo Fill (pre-order collected at Silo, vehicle must be near SILO) ──
-- siloNode: world node to use as vehicle search origin (silo's root node).
-- Returns: success (bool), message key (string), actualLiters (number)
function DepotSystem:buyFromSilo(depotId, siloNode, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if not g_server then return false, "fd_error_server", 0 end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot", 0 end

    if not siloNode then return false, "fd_error_depot", 0 end

    local liters = math.max(DepotConstants.MIN_PURCHASE_LITERS,
                   math.min(DepotConstants.MAX_PURCHASE_LITERS, requestedLiters))

    local px, _, pz = getWorldTranslation(siloNode)
    local vehicle, unitIndex = findVehicleNearPosition(px, pz, fillTypeIndex, false)
    if not vehicle then return false, "fd_depot_no_trailer", 0 end

    local freeCapacity = vehicle:getFillUnitFreeCapacity(unitIndex)
    if freeCapacity <= 0 then return false, "fd_depot_tank_full", 0 end
    liters = math.min(liters, freeCapacity)

    local cost = self._pricing:calculateBuyCost(fillTypeName, liters)

    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if not farm then return false, "fd_error_farm", 0 end
    if farm.balance < cost then return false, "fd_depot_no_money", 0 end

    local fromStorage = math.min(liters, depot.storageLevel[fillTypeName] or 0)
    if fromStorage > 0 then
        depot.storageLevel[fillTypeName] = (depot.storageLevel[fillTypeName] or 0) - fromStorage
    end

    g_currentMission:addMoney(-cost, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)
    vehicle:addFillUnitFillLevel(farmId, unitIndex, liters, fillTypeIndex,
                                 ToolType.UNDEFINED, nil)

    return true, "fd_depot_buy_success", liters
end

-- ─── Sell Transaction ────────────────────────────────────
-- Returns: success (bool), message key (string), liters sold (number), revenue (number)
function DepotSystem:sellFillType(depotId, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if not g_server then return false, "fd_error_server", 0, 0 end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot", 0, 0 end

    local vehicle, unitIndex = self:findCompatibleVehicle(depotId, fillTypeIndex, true)
    if not vehicle then return false, "fd_depot_no_trailer", 0, 0 end

    local available = vehicle:getFillUnitFillLevel(unitIndex)
    if available <= 0 then return false, "fd_depot_tank_empty", 0, 0 end

    local liters = math.min(requestedLiters or available, available)

    local cap = (g_DepotManager and g_DepotManager.settings.storageCapacity)
                or DepotConstants.STORAGE_CAPACITY
    local currentStored = depot.storageLevel[fillTypeName] or 0
    local space = cap - currentStored
    liters = math.min(liters, math.max(0, space))
    if liters <= 0 then return false, "fd_depot_storage_full", 0, 0 end

    local revenue = self._pricing:calculateSellRevenue(fillTypeName, liters)

    vehicle:addFillUnitFillLevel(farmId, unitIndex, -liters, fillTypeIndex,
                                 ToolType.UNDEFINED, nil)

    depot.storageLevel[fillTypeName] = currentStored + liters

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
