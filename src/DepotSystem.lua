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
local function vehicleFillUnitAccepts(veh, fuIdx, fillTypeIndex)
    if veh.getFillUnitSupportsFillType == nil then return false end
    return veh:getFillUnitSupportsFillType(fuIdx, fillTypeIndex)
end

local function findVehicleNearPosition(px, pz, fillTypeIndex, forSell)
    if not g_currentMission then return nil, nil end

    local vehicleList = g_currentMission.vehicleSystem and g_currentMission.vehicleSystem.vehicles or {}
    local totalVehicles, inRange, rejectType, rejectFull = 0, 0, 0, 0

    for _, vehicle in ipairs(vehicleList) do
        if vehicle and vehicle.rootNode then
            totalVehicles = totalVehicles + 1
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            local dx, dz = vx - px, vz - pz
            local distSq = dx * dx + dz * dz
            DepotLogger.debug("  vehicle '%s' dist=%.1fm (limit=60m) inRange=%s",
                tostring(vehicle.typeName or "?"), math.sqrt(distSq), tostring(distSq <= VEHICLE_SEARCH_RADIUS_SQ))
            if distSq <= VEHICLE_SEARCH_RADIUS_SQ then
                inRange = inRange + 1
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
                                local accepts = vehicleFillUnitAccepts(veh, fuIdx, fillTypeIndex)
                                local free = accepts and (veh:getFillUnitFreeCapacity(fuIdx) or 0) or 0
                                DepotLogger.debug("    fu[%d] fillType=%s accepts=%s free=%.0f",
                                    fuIdx, tostring(fillUnit.fillType), tostring(accepts), free)
                                if accepts and free > 0 then
                                    return veh, fuIdx
                                elseif not accepts then
                                    rejectType = rejectType + 1
                                elseif free <= 0 then
                                    rejectFull = rejectFull + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    DepotLogger.info("Vehicle search failed: origin=(%.0f,%.0f) ftIdx=%s total=%d inRange=%d rejectType=%d rejectFull=%d",
        px, pz, tostring(fillTypeIndex), totalVehicles, inRange, rejectType, rejectFull)
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

    -- Resolve fillTypeIndex from name to avoid SoilFertilizer index drift
    if g_fillTypeManager then
        local resolvedIdx = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if resolvedIdx and resolvedIdx > 0 then
            fillTypeIndex = resolvedIdx
        end
    end

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
    if farm:getBalance() < cost then return false, "fd_depot_no_money", 0 end

    local fromStorage = math.min(liters, depot.storageLevel[fillTypeName] or 0)
    if fromStorage > 0 then
        depot.storageLevel[fillTypeName] = (depot.storageLevel[fillTypeName] or 0) - fromStorage
    end

    g_currentMission:addMoney(-cost, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)
    local actualFilled = vehicle:addFillUnitFillLevel(farmId, unitIndex, liters, fillTypeIndex,
                                                      ToolType.UNDEFINED, nil)
    DepotLogger.info("Depot fill result: vehicle='%s' fu=%d requested=%.0f filled=%.0f type=%s",
        tostring(vehicle.typeName or "?"), unitIndex, liters, actualFilled or 0, fillTypeName)

    return true, "fd_depot_buy_success", actualFilled or liters
end

-- ─── Silo Fill (pre-order collected at Silo, vehicle must be near SILO) ──
-- siloNode: world node to use as vehicle search origin (silo's root node).
-- Returns: success (bool), message key (string), actualLiters (number)
function DepotSystem:buyFromSilo(depotId, siloNode, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if not g_server then return false, "fd_error_server", 0 end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot", 0 end

    local liters = math.max(DepotConstants.MIN_PURCHASE_LITERS,
                   math.min(DepotConstants.MAX_PURCHASE_LITERS, requestedLiters))

    -- Resolve fillTypeIndex from name in case the index drifted (e.g. SoilFertilizer remapping)
    if g_fillTypeManager then
        local resolvedIdx = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if resolvedIdx and resolvedIdx > 0 then
            fillTypeIndex = resolvedIdx
        end
    end

    local vehicle, unitIndex = nil, nil

    -- 1st: search near the silo (player walked up on foot)
    if siloNode then
        local px, _, pz = getWorldTranslation(siloNode)
        vehicle, unitIndex = findVehicleNearPosition(px, pz, fillTypeIndex, false)
    end

    -- 2nd fallback: search near the depot node itself (sprayer parked at depot)
    if not vehicle then
        local depotPlaceable = g_DepotManager and g_DepotManager.depots[depotId]
        local depotNode = depotPlaceable and depotPlaceable.rootNode
        if depotNode then
            local px, _, pz = getWorldTranslation(depotNode)
            vehicle, unitIndex = findVehicleNearPosition(px, pz, fillTypeIndex, false)
        end
    end

    -- 3rd fallback: search near every registered unload node for this depot
    if not vehicle then
        local unloadNode = g_DepotManager and g_DepotManager.depotUnloadNodes[depotId]
        if unloadNode then
            local px, _, pz = getWorldTranslation(unloadNode)
            vehicle, unitIndex = findVehicleNearPosition(px, pz, fillTypeIndex, false)
        end
    end

    if not vehicle then return false, "fd_depot_no_trailer", 0 end

    local freeCapacity = vehicle:getFillUnitFreeCapacity(unitIndex)
    if freeCapacity <= 0 then return false, "fd_depot_tank_full", 0 end
    liters = math.min(liters, freeCapacity)

    local cost = self._pricing:calculateBuyCost(fillTypeName, liters)

    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if not farm then return false, "fd_error_farm", 0 end
    if farm:getBalance() < cost then return false, "fd_depot_no_money", 0 end

    local fromStorage = math.min(liters, depot.storageLevel[fillTypeName] or 0)
    if fromStorage > 0 then
        depot.storageLevel[fillTypeName] = (depot.storageLevel[fillTypeName] or 0) - fromStorage
    end

    g_currentMission:addMoney(-cost, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)
    local actualFilled = vehicle:addFillUnitFillLevel(farmId, unitIndex, liters, fillTypeIndex,
                                                      ToolType.UNDEFINED, nil)
    DepotLogger.info("Silo fill result: vehicle='%s' fu=%d requested=%.0f filled=%.0f type=%s",
        tostring(vehicle.typeName or "?"), unitIndex, liters, actualFilled or 0, fillTypeName)

    return true, "fd_depot_buy_success", actualFilled or liters
end

-- ─── Product Order (bigBag / liquidTank spawn) ───────────
-- Deducts storage, charges farm, spawns one or more physical pallet objects near the depot.
-- Returns: success (bool), message key (string)
function DepotSystem:orderProduct(depotId, fillTypeName, fillTypeIndex, quantity, spawnX, spawnZ, farmId)
    if not g_server then return false, "fd_error_server" end

    local depot = self._depots[depotId]
    if not depot then return false, "fd_error_depot" end

    -- Resolve index from name (guard against SF drift)
    if g_fillTypeManager then
        local resolvedIdx = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if resolvedIdx and resolvedIdx > 0 then
            fillTypeIndex = resolvedIdx
        end
    end

    local fillType = g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    if not fillType or not fillType.palletFilename or fillType.palletFilename == "" then
        return false, "fd_products_no_object"
    end

    quantity = math.max(1, math.min(DepotConstants.MAX_PRODUCT_QUANTITY, quantity or 1))
    local litresNeeded = quantity * DepotConstants.PRODUCT_LITRES_PER_UNIT

    local stored = depot.storageLevel[fillTypeName] or 0
    if stored < litresNeeded then return false, "fd_products_no_stock" end

    local cost = self._pricing:calculateBuyCost(fillTypeName, litresNeeded)
    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if not farm then return false, "fd_error_farm" end
    if farm:getBalance() < cost then return false, "fd_depot_no_money" end

    depot.storageLevel[fillTypeName] = stored - litresNeeded
    g_currentMission:addMoney(-cost, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)

    -- Spawn objects side by side (1.5m apart along world X)
    local palletFile = fillType.palletFilename
    for i = 1, quantity do
        local offsetX = (i - 1) * 1.5
        local data = VehicleLoadingData.new()
        data:setFilename(palletFile)
        data:setPosition(spawnX + offsetX, nil, spawnZ)  -- nil Y = terrain height auto-resolve
        data:setPropertyState(VehiclePropertyState.OWNED)
        data:setOwnerFarmId(farmId)
        data:load(function(_, vehicles, state, _)
            if state ~= VehicleLoadingState.OK then
                DepotLogger.warning("Product spawn failed for %s unit %d/%d",
                    fillTypeName, i, quantity)
            end
        end)
    end

    DepotLogger.info("Product order: %s ×%d (%.0fL) cost=$%.2f farm=%d",
        fillTypeName, quantity, litresNeeded, cost, farmId)

    return true, "fd_products_ordered"
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
        local cap = (g_DepotManager and g_DepotManager.settings.storageCapacity) or DepotConstants.STORAGE_CAPACITY
        depot.storageLevel[name] = math.max(0, math.min(cap, liters))
        i = i + 1
    end
end
