-- =========================================================
-- FS25 Fertilizer Depot - Delivery System
-- =========================================================
-- Manages player-driven stock replenishment deliveries.
-- Flow: ORDER tab → place order → drive to DepotPickup zone
--       → confirm pickup (money deducted) → drive back to depot
--       → complete delivery (stock added, optional truck despawned).
--
-- Server-authoritative. Clients receive state via DepotDeliverySyncEvent.

---@class DeliverySystem
DeliverySystem = {}
local DeliverySystem_mt = Class(DeliverySystem)

-- Delivery status codes (serialised as UInt8 in sync events)
DeliverySystem.STATUS = {
    NONE    = 0,  -- no active delivery
    PENDING = 1,  -- order placed; truck spawned (or player uses own vehicle); drive to pickup zone
    LOADED  = 2,  -- goods collected at pickup; player driving back to depot
}

function DeliverySystem.new(depotSystem, pricing, sfBridge, settings)
    local self = setmetatable({}, DeliverySystem_mt)
    self.depotSystem = depotSystem
    self.pricing     = pricing
    self.sfBridge    = sfBridge
    self.settings    = settings
    self.deliveries  = {}   -- [depotId] = delivery record
    return self
end

-- ─── Order Calculation ───────────────────────────────────

-- Returns {items, baseCost, deliveryCost, fee} for what is currently needed at depotId.
-- items = { {fillTypeName, fillTypeIndex, displayName, stored, needed, baseCost}, ... }
function DeliverySystem:calculateOrder(depotId)
    local items      = {}
    local baseCost   = 0
    local cap        = (self.settings and self.settings.storageCapacity) or DepotConstants.STORAGE_CAPACITY
    local fillTypes  = self.sfBridge and self.sfBridge:getFillTypeList() or {}
    local minLiters  = DepotConstants.DELIVERY.MIN_ORDER_LITERS

    for _, ft in ipairs(fillTypes) do
        local stored = self.depotSystem:getStorageLevel(depotId, ft.name) or 0
        local needed = math.max(0, cap - stored)
        if needed >= minLiters then
            local price = self.pricing:getBuyPrice(ft.name)
            local cost  = price * needed
            baseCost = baseCost + cost
            table.insert(items, {
                fillTypeName  = ft.name,
                fillTypeIndex = ft.fillTypeIndex,
                displayName   = ft.displayName or ft.name,
                stored        = stored,
                needed        = needed,
                baseCost      = cost,
            })
        end
    end

    local surcharge = DepotConstants.DELIVERY.SURCHARGE
    return {
        items        = items,
        baseCost     = baseCost,
        deliveryCost = baseCost * surcharge,
        fee          = baseCost * (surcharge - 1.0),
    }
end

-- ─── Validation ──────────────────────────────────────────

-- Returns nil if order can be placed, or a localisation key describing why it cannot.
function DeliverySystem:canPlaceOrder(depotId, farmId)
    if self.deliveries[depotId] then
        return "fd_delivery_already_active"
    end
    -- Pickup zone must be registered
    if not g_DepotManager or not next(g_DepotManager.pickupNodes or {}) then
        return "fd_delivery_no_pickup"
    end
    local order = self:calculateOrder(depotId)
    if #order.items == 0 then
        return "fd_delivery_stock_full"
    end
    return nil
end

-- ─── Server Transactions ─────────────────────────────────

-- Place a new delivery order. Returns success, optional error key.
function DeliverySystem:placeOrder(depotId, farmId)
    local blockKey = self:canPlaceOrder(depotId, farmId)
    if blockKey then return false, blockKey end

    local order = self:calculateOrder(depotId)
    self.deliveries[depotId] = {
        status       = DeliverySystem.STATUS.PENDING,
        depotId      = depotId,
        farmId       = farmId,
        items        = order.items,
        baseCost     = order.baseCost,
        deliveryCost = order.deliveryCost,
        vehicle      = nil,
    }
    DepotLogger.info("Delivery order placed: depot=%d farm=%d types=%d total=$%.2f",
        depotId, farmId, #order.items, order.deliveryCost)

    local spawnOk, spawnErr = pcall(function() self:spawnDeliveryVehicle(depotId, farmId) end)
    if not spawnOk then
        DepotLogger.warning("spawnDeliveryVehicle error (delivery still active): %s", tostring(spawnErr))
    end
    return true
end

-- Spawn the delivery truck at the depot unload zone (async via VehicleLoadingData).
-- Assigns rec.vehicle once the truck is ready. Safe to cancel before callback fires.
function DeliverySystem:spawnDeliveryVehicle(depotId, farmId)
    local truckXml = DepotConstants.DELIVERY.TRUCK_XML
    if not truckXml or truckXml == "" then
        DepotLogger.warning("No TRUCK_XML configured — delivery vehicle will not spawn")
        return
    end

    local spawnX, spawnZ = 0, 0
    local offset = DepotConstants.DELIVERY.TRUCK_SPAWN_OFFSET or 8.0
    local unloadNode = g_DepotManager and g_DepotManager.depotUnloadNodes[depotId]
    local depotPlaceable = g_DepotManager and g_DepotManager.depots[depotId]
    local refNode = unloadNode or (depotPlaceable and depotPlaceable.rootNode)
    if refNode then
        local ok, wx, wy, wz = pcall(getWorldTranslation, refNode)
        if ok and wx then
            spawnX = wx + offset
            spawnZ = wz
        end
    end

    local data = VehicleLoadingData.new()
    data:setFilename(truckXml)
    data:setPosition(spawnX, nil, spawnZ)
    data:setPropertyState(VehiclePropertyState.OWNED)
    data:setOwnerFarmId(farmId)
    data:load(function(_, vehicles, state, _)
        if state ~= VehicleLoadingState.OK or not vehicles or #vehicles == 0 then
            DepotLogger.warning("Delivery truck spawn failed: depot=%d state=%s",
                depotId, tostring(state))
            return
        end
        local rec = self.deliveries[depotId]
        if not rec then
            -- Order was cancelled before the async callback returned — clean up immediately
            for _, veh in ipairs(vehicles) do veh:delete() end
            return
        end
        rec.vehicle = vehicles[1]
        DepotLogger.info("Delivery truck spawned: depot=%d", depotId)
        if g_currentMission and g_currentMission.showBlinkingWarning then
            g_currentMission:showBlinkingWarning("Delivery truck ready at your depot!", 4000)
        end
    end)
end

-- Confirm pickup at the supplier zone. Deducts money, transitions to LOADED.
function DeliverySystem:confirmPickup(depotId, farmId)
    local rec = self.deliveries[depotId]
    if not rec then return false, "fd_delivery_none" end
    if rec.status ~= DeliverySystem.STATUS.PENDING then return false, "fd_delivery_wrong_status" end
    if rec.farmId ~= farmId then return false, "fd_delivery_wrong_farm" end

    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if not farm then return false, "fd_error_farm" end
    if farm:getBalance() < rec.deliveryCost then return false, "fd_depot_no_money" end

    g_currentMission:addMoney(-rec.deliveryCost, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)
    rec.status = DeliverySystem.STATUS.LOADED

    DepotLogger.info("Delivery picked up: depot=%d farm=%d $%.2f deducted",
        depotId, farmId, rec.deliveryCost)
    return true
end

-- Complete delivery at the depot. Adds stock, despawns vehicle, clears record.
function DeliverySystem:completeDelivery(depotId, farmId)
    local rec = self.deliveries[depotId]
    if not rec then return false, "fd_delivery_none" end
    if rec.status ~= DeliverySystem.STATUS.LOADED then return false, "fd_delivery_wrong_status" end
    if rec.farmId ~= farmId then return false, "fd_delivery_wrong_farm" end

    local cap = (self.settings and self.settings.storageCapacity) or DepotConstants.STORAGE_CAPACITY
    for _, item in ipairs(rec.items) do
        local current = self.depotSystem:getStorageLevel(depotId, item.fillTypeName) or 0
        self.depotSystem:setStorageLevel(depotId, item.fillTypeName,
            math.min(cap, current + item.needed))
    end

    if rec.vehicle then
        rec.vehicle:delete()
        rec.vehicle = nil
    end

    local typeCount = #rec.items
    self.deliveries[depotId] = nil
    DepotLogger.info("Delivery completed: depot=%d %d types restocked", depotId, typeCount)
    return true, typeCount
end

-- Cancel an active delivery. Applies a cost penalty if delivery is PENDING.
-- No penalty if delivery is LOADED (money already paid; goods were collected).
function DeliverySystem:cancelDelivery(depotId, farmId)
    local rec = self.deliveries[depotId]
    if not rec then return false, "fd_delivery_none" end
    if rec.farmId ~= farmId then return false, "fd_delivery_wrong_farm" end

    local penalty = 0
    if rec.status == DeliverySystem.STATUS.PENDING then
        penalty = rec.deliveryCost * DepotConstants.DELIVERY.CANCEL_PENALTY
        if penalty > 0 then
            local farm = g_farmManager and g_farmManager:getFarmById(farmId)
            if farm and farm:getBalance() >= penalty then
                g_currentMission:addMoney(-penalty, farmId, MoneyType.PURCHASE_FERTILIZER, true, true)
            end
        end
    end

    if rec.vehicle then
        rec.vehicle:delete()
        rec.vehicle = nil
    end

    self.deliveries[depotId] = nil
    DepotLogger.info("Delivery cancelled: depot=%d penalty=$%.2f", depotId, penalty)
    return true, penalty
end

-- ─── Queries ─────────────────────────────────────────────

function DeliverySystem:getDelivery(depotId)
    return self.deliveries[depotId]
end

-- Returns true when the delivery truck (if any) is close enough to the depot
-- unload node to allow the player to complete the delivery.
-- Phase 1: always true when status=LOADED and no real truck is tracked.
-- Phase 4: performs a world-space proximity check on rec.vehicle.
function DeliverySystem:isDeliveryTruckNearDepot(depotId)
    local rec = self.deliveries[depotId]
    if not rec or rec.status ~= DeliverySystem.STATUS.LOADED then return false end
    if not rec.vehicle then return true end   -- Phase 1: no truck = player's own vehicle = always OK

    local unloadNode = g_DepotManager and g_DepotManager.depotUnloadNodes[depotId]
    if not unloadNode then return true end
    local uok, ux, uy, uz = pcall(getWorldTranslation, unloadNode)
    if not uok or not ux then return true end
    local vok, vx, vy, vz = pcall(getWorldTranslation, rec.vehicle.rootNode)
    if not vok or not vx then return true end
    local dist = math.sqrt((vx - ux)^2 + (vz - uz)^2)
    return dist <= DepotConstants.DELIVERY.TRUCK_DEPOT_RANGE
end

-- Returns distance (metres) from the delivery truck to the depot unload node, or nil.
function DeliverySystem:getDeliveryTruckDistance(depotId)
    local rec = self.deliveries[depotId]
    if not rec or rec.status ~= DeliverySystem.STATUS.LOADED then return nil end
    if not rec.vehicle then return nil end

    local unloadNode = g_DepotManager and g_DepotManager.depotUnloadNodes[depotId]
    if not unloadNode then return nil end
    local uok, ux, uy, uz = pcall(getWorldTranslation, unloadNode)
    if not uok then return nil end
    local vok, vx, vy, vz = pcall(getWorldTranslation, rec.vehicle.rootNode)
    if not vok then return nil end
    return math.sqrt((vx - ux)^2 + (vz - uz)^2)
end

-- ─── Save / Load ─────────────────────────────────────────

function DeliverySystem:saveDeliveryToXML(xmlFile, key, depotId)
    local rec = self.deliveries[depotId]
    if not rec or rec.status == DeliverySystem.STATUS.NONE then
        xmlFile:setInt(key .. "#status", 0)
        return
    end
    xmlFile:setInt(key .. "#status",    rec.status)
    xmlFile:setInt(key .. "#farmId",    rec.farmId)
    xmlFile:setFloat(key .. "#baseCost",     rec.baseCost)
    xmlFile:setFloat(key .. "#deliveryCost", rec.deliveryCost)
    for i, item in ipairs(rec.items) do
        local iKey = string.format("%s.item(%d)", key, i - 1)
        xmlFile:setString(iKey .. "#name",   item.fillTypeName)
        xmlFile:setFloat(iKey  .. "#liters", item.needed)
        xmlFile:setFloat(iKey  .. "#cost",   item.baseCost)
    end
    DepotLogger.info("Delivery state saved: depot=%d status=%d", depotId, rec.status)
end

function DeliverySystem:loadDeliveryFromXML(xmlFile, key, depotId)
    local status = xmlFile:getInt(key .. "#status", 0)
    if status == 0 then return end

    local farmId       = xmlFile:getInt(key .. "#farmId", 1)
    local baseCost     = xmlFile:getFloat(key .. "#baseCost", 0)
    local deliveryCost = xmlFile:getFloat(key .. "#deliveryCost", 0)

    local items = {}
    local i = 0
    while true do
        local iKey = string.format("%s.item(%d)", key, i)
        local name = xmlFile:getString(iKey .. "#name")
        if not name or name == "" then break end
        local liters = xmlFile:getFloat(iKey .. "#liters", 0)
        local cost   = xmlFile:getFloat(iKey .. "#cost",   0)
        -- Re-resolve index from name to guard against fill type drift
        local ftIdx = 0
        if g_fillTypeManager then
            ftIdx = g_fillTypeManager:getFillTypeIndexByName(name) or 0
        end
        table.insert(items, {
            fillTypeName  = name,
            fillTypeIndex = ftIdx,
            displayName   = name,
            stored        = 0,
            needed        = liters,
            baseCost      = cost,
        })
        i = i + 1
    end

    self.deliveries[depotId] = {
        status       = status,
        depotId      = depotId,
        farmId       = farmId,
        items        = items,
        baseCost     = baseCost,
        deliveryCost = deliveryCost,
        vehicle      = nil,
    }
    DepotLogger.info("Delivery state restored: depot=%d status=%d types=%d", depotId, status, #items)
end
