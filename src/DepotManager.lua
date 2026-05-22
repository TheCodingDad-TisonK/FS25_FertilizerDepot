-- =========================================================
-- FS25 Fertilizer Depot - Manager Singleton
-- =========================================================

local _depotMgrModName = g_currentModName

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[_depotMgrModName]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key)
           and not text:find("^Missing '") then
            return text
        end
    end
    return fallback or key
end

-- Scan vehicle + all attached implements for the first fertilizer fill unit.
local function findFertilizerInVehicle(vehicle, sfBridge)
    local fillTypeList = sfBridge and sfBridge:getFillTypeList() or {}
    local knownTypes = {}
    for _, ft in ipairs(fillTypeList) do knownTypes[ft.name] = true end

    local function scan(v)
        local spec = v.spec_fillUnit
        if spec and spec.fillUnits then
            for fuIdx, fu in ipairs(spec.fillUnits) do
                local lvl = fu.fillLevel or 0
                if lvl > 0 and fu.fillType and fu.fillType > 0 then
                    local ftName = g_fillTypeManager and
                                   g_fillTypeManager:getFillTypeNameByIndex(fu.fillType)
                    if ftName and knownTypes[ftName] then
                        return {
                            vehicle      = v,
                            unitIndex    = fuIdx,
                            fillTypeIndex= fu.fillType,
                            fillTypeName = ftName,
                            amount       = lvl,
                        }
                    end
                end
            end
        end
        if v.getAttachedImplements then
            for _, impl in pairs(v:getAttachedImplements() or {}) do
                if impl and impl.object then
                    local res = scan(impl.object)
                    if res then return res end
                end
            end
        end
        return nil
    end

    return scan(vehicle)
end

---@class DepotManager
DepotManager = {}
local DepotManager_mt = Class(DepotManager)

local PROXIMITY_THRESHOLD     = 5.0    -- metres, depot & silo on-foot radius (keep < gate distance)
local SILO_VEHICLE_PROXIMITY  = 10.0   -- metres, vehicle near silo (larger — harder to park precisely)
local VEHICLE_UNLOAD_PROXIMITY= 8.0    -- metres, vehicle near depot unload marker
local SILO_FILL_COOLDOWN      = 2000   -- ms between silo fill triggers
local DEPOT_SELL_COOLDOWN     = 5000   -- ms cooldown after sell dialog closes

function DepotManager.new()
    local self = setmetatable({}, DepotManager_mt)
    self.settings     = DepotSettings.new()
    self.sfBridge     = SoilFertilizerBridge.new()
    self.pricing      = DepotPricing.new(self.sfBridge)
    self.depotSystem  = DepotSystem.new(self.pricing)
    self.deliverySystem = nil   -- created in initialize() after all singletons exist

    self.depots       = {}
    self.depotNodes   = {}
    self.depotUnloadNodes = {}
    self.depotProductSpawnNodes = {}
    self.silos        = {}
    self.siloNodes    = {}
    self._nextSiloId  = 1

    -- Pickup zone registry (PlaceableDepotPickup instances)
    self.pickupPlaceables = {}
    self.pickupNodes      = {}
    self._nextPickupId    = 1

    self.pendingOrders = {}
    self.activeDialog  = nil

    self._initialized       = false
    self._nearDepotId       = nil
    self._nearSiloId        = nil       -- on-foot silo proximity
    self._nearVehicleSiloId = nil       -- vehicle silo proximity (auto-trigger)
    self._nearUnloadDepotId = nil
    self._nearPickupId      = nil       -- on-foot pickup zone proximity
    self._proximityTimer    = 0
    self._settingsEventId   = nil

    -- Single persistent ACTIVATE_HANDTOOL event (shared for depot + silo + pickup)
    self._interactEventId  = nil
    self._siloFillCooldown = 0
    self._depotSellCooldown= 0

    -- Pending context for YesNo callbacks
    self._pendingSiloFill       = nil
    self._pendingDepotSell      = nil
    self._pendingDeliveryPickup = nil

    self.hud = nil   -- created in initialize()

    return self
end

function DepotManager:initialize()
    if self._initialized then return end
    self._initialized = true
    self.deliverySystem = DeliverySystem.new(
        self.depotSystem, self.pricing, self.sfBridge, self.settings)
    self.hud = DepotHUD.new()
    DepotLogger.info("DepotManager initialized (SF installed: %s)",
        tostring(self.sfBridge:isInstalled()))
    addConsoleCommand("SoilDebugDepot",   "Toggle FertDepot debug logging",            "cmdDebugDepot",      self)
    addConsoleCommand("FDFillStock",      "Fill all depot storage to max [depotId]",   "cmdFDFillStock",     self)
    addConsoleCommand("FDEmptyStock",     "Empty all depot storage [depotId]",         "cmdFDEmptyStock",    self)
    addConsoleCommand("FDCancelDelivery", "Cancel active delivery for depot [depotId]","cmdFDCancelDelivery",self)
end

function DepotManager:delete()
    if self.activeDialog then
        self.activeDialog:close()
        self.activeDialog = nil
    end
    if self.hud then
        self.hud:delete()
        self.hud = nil
    end
    if self._interactEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self._interactEventId)
        self._interactEventId = nil
    end
    self.sfBridge:invalidateCache()
    DepotLogger.info("DepotManager deleted")
end

-- ─── Depot Registration ──────────────────────────────────

function DepotManager:registerDepot(placeableDepot)
    local id = self.depotSystem:registerDepot()
    self.depots[id] = placeableDepot
    placeableDepot.depotId = id
    local spec = placeableDepot[PlaceableDepot.SPEC_TABLE_NAME]
    self.depotNodes[id] = (spec and spec.playerTriggerNode) or placeableDepot.rootNode
    DepotLogger.info("Depot #%d registered", id)
    return id
end

function DepotManager:unregisterDepot(depotId)
    self.depotSystem:unregisterDepot(depotId)
    self.depots[depotId] = nil
    self.depotNodes[depotId] = nil
    self.depotUnloadNodes[depotId] = nil
    self.depotProductSpawnNodes[depotId] = nil
    if self._nearDepotId == depotId then
        self._nearDepotId = nil
        self:_updateInteractPrompt()
    end
    if self._nearUnloadDepotId == depotId then
        self._nearUnloadDepotId = nil
    end
    DepotLogger.info("Depot #%d unregistered", depotId)
end

function DepotManager:registerDepotUnloadNode(depotId, node)
    self.depotUnloadNodes[depotId] = node
    DepotLogger.info("Depot #%d unload node registered: %s", depotId, tostring(node))
end

function DepotManager:registerDepotProductSpawnNode(depotId, node)
    self.depotProductSpawnNodes[depotId] = node
    DepotLogger.info("Depot #%d product spawn node registered: %s", depotId, tostring(node))
end

-- ─── Pickup Zone Registration ────────────────────────────

function DepotManager:registerPickup(placeablePickup)
    local id = self._nextPickupId
    self._nextPickupId = self._nextPickupId + 1
    self.pickupPlaceables[id] = placeablePickup
    local spec = placeablePickup[PlaceableDepotPickup.SPEC_TABLE_NAME]
    self.pickupNodes[id] = (spec and spec.playerTriggerNode) or placeablePickup.rootNode
    DepotLogger.info("Pickup zone #%d registered", id)
    return id
end

function DepotManager:unregisterPickup(pickupId)
    self.pickupPlaceables[pickupId] = nil
    self.pickupNodes[pickupId] = nil
    if self._nearPickupId == pickupId then
        self._nearPickupId = nil
        self:_updateInteractPrompt()
    end
    DepotLogger.info("Pickup zone #%d unregistered", pickupId)
end

-- ─── Silo Registration ───────────────────────────────────

function DepotManager:registerSilo(placeableSilo, loadStationNode)
    local id = self._nextSiloId
    self._nextSiloId = self._nextSiloId + 1
    self.silos[id] = placeableSilo
    self.siloNodes[id] = loadStationNode or placeableSilo.rootNode
    DepotLogger.info("Silo #%d registered (loadStation node: %s)", id, tostring(self.siloNodes[id]))
    return id
end

function DepotManager:unregisterSilo(siloId)
    self.silos[siloId] = nil
    self.siloNodes[siloId] = nil
    if self._nearSiloId == siloId then
        self._nearSiloId = nil
        self:_updateInteractPrompt()
    end
    if self._nearVehicleSiloId == siloId then
        self._nearVehicleSiloId = nil
    end
    DepotLogger.info("Silo #%d unregistered", siloId)
end

-- ─── Pending Orders ──────────────────────────────────────

function DepotManager:setPendingOrder(farmId, depotId, fillTypeName, fillTypeIndex, maxLiters, displayName)
    self.pendingOrders[farmId] = {
        depotId      = depotId,
        fillTypeName  = fillTypeName,
        fillTypeIndex = fillTypeIndex,
        maxLiters     = maxLiters,
        displayName   = displayName or fillTypeName,
    }
    self:_updateInteractPrompt()
    DepotLogger.info("Pending order set for farm %d: %s %.0fL", farmId, fillTypeName, maxLiters)
end

function DepotManager:getPendingOrder(farmId)
    return self.pendingOrders[farmId]
end

function DepotManager:clearPendingOrder(farmId)
    self.pendingOrders[farmId] = nil
    self:_updateInteractPrompt()
end

-- ─── Network Helpers ─────────────────────────────────────

function DepotManager:broadcastSync(depotId)
    DepotSyncEvent.broadcast(depotId)
end

-- ─── Dialog Management ───────────────────────────────────

function DepotManager:openDialog(depotId)
    DepotLogger.info("openDialog called for depot #%s", tostring(depotId))
    if self.activeDialog then
        self.activeDialog:close()
        self.activeDialog = nil
    end
    DepotDialog.show(depotId)
    self.activeDialog = DepotDialog.getInstance()
end

function DepotManager:closeDialog()
    if self.activeDialog then
        self.activeDialog:close()
        self.activeDialog = nil
    end
end

function DepotManager:openSettingsDialog()
    DepotSettingsDialog.show()
end

-- ─── Update ──────────────────────────────────────────────

function DepotManager:update(dt)
    if self.hud then self.hud:update(dt) end

    if self._siloFillCooldown > 0 then
        self._siloFillCooldown = self._siloFillCooldown - dt
    end
    if self._depotSellCooldown > 0 then
        self._depotSellCooldown = self._depotSellCooldown - dt
    end

    self._proximityTimer = self._proximityTimer + dt
    if self._proximityTimer < 500 then return end
    self._proximityTimer = 0

    self:_checkDepotProximity()
    self:_checkSiloProximity()
    self:_checkPickupProximity()
    self:_checkDepotVehicles()
end

-- ─── Single Persistent Interact Action ───────────────────

function DepotManager:_getOrRegisterInteractEvent()
    if self._interactEventId then return self._interactEventId end
    if not g_inputBinding then return nil end

    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    local ok, evId = g_inputBinding:registerActionEvent(
        InputAction.FD_INTERACT, self,
        DepotManager._onInteractAction, false, true, false, true)
    if ok and evId then
        self._interactEventId = evId
        g_inputBinding:setActionEventTextVisibility(evId, false)
        g_inputBinding:setActionEventActive(evId, false)
        DepotLogger.info("FD_INTERACT registered (id=%s)", tostring(evId))
    end
    g_inputBinding:endActionEventsModification()
    return self._interactEventId
end

function DepotManager:_updateInteractPrompt()
    local evId = self:_getOrRegisterInteractEvent()
    if not evId or not g_inputBinding then return end

    local farmId = g_localPlayer and g_localPlayer.farmId or 0

    -- Silo takes priority when on foot near silo
    if self._nearSiloId then
        local order = self.pendingOrders[farmId]
        if order then
            local label = string.format(
                tr("fd_silo_collect_action", "Collect %s (%.0fL)"),
                order.displayName, order.maxLiters)
            g_inputBinding:setActionEventText(evId, label)
            g_inputBinding:setActionEventTextVisibility(evId, true)
            g_inputBinding:setActionEventActive(evId, true)
            return
        else
            g_inputBinding:setActionEventText(evId,
                tr("fd_silo_no_order", "No pending order. Confirm a type at the Depot first."))
            g_inputBinding:setActionEventTextVisibility(evId, true)
            g_inputBinding:setActionEventActive(evId, false)
            return
        end
    end

    -- Pickup zone: show collect prompt when a PENDING delivery exists for this farm
    if self._nearPickupId then
        local farmId = g_localPlayer and g_localPlayer.farmId or 0
        local hasDelivery = false
        if self.deliverySystem then
            for _, rec in pairs(self.deliverySystem.deliveries) do
                if rec.farmId == farmId and rec.status == DeliverySystem.STATUS.PENDING then
                    hasDelivery = true
                    break
                end
            end
        end
        if hasDelivery then
            g_inputBinding:setActionEventText(evId,
                tr("fd_delivery_pickup_action", "Collect Delivery"))
            g_inputBinding:setActionEventTextVisibility(evId, true)
            g_inputBinding:setActionEventActive(evId, true)
        else
            g_inputBinding:setActionEventText(evId,
                tr("fd_delivery_no_pending", "No pending delivery."))
            g_inputBinding:setActionEventTextVisibility(evId, true)
            g_inputBinding:setActionEventActive(evId, false)
        end
        return
    end

    -- Depot dialog (only when inside building via physical trigger)
    if self._nearDepotId then
        g_inputBinding:setActionEventText(evId,
            tr("fd_depot_open_action", "Open Fertilizer Depot"))
        g_inputBinding:setActionEventTextVisibility(evId, true)
        g_inputBinding:setActionEventActive(evId, true)
        return
    end

    -- Nothing nearby — hide prompt
    g_inputBinding:setActionEventTextVisibility(evId, false)
    g_inputBinding:setActionEventActive(evId, false)
end

function DepotManager:_onInteractAction()
    -- Silo fill (on foot E-key path)
    if self._nearSiloId then
        if self._siloFillCooldown > 0 then return end
        local farmId = g_localPlayer and g_localPlayer.farmId or 0
        local order = self.pendingOrders[farmId]
        if not order then return end
        self:_tryShowSiloFillDialog(self._nearSiloId, farmId, order)
        return
    end

    -- Delivery pickup at supplier zone
    if self._nearPickupId then
        self:_tryShowDeliveryPickupDialog()
        return
    end

    -- Depot open
    if self._nearDepotId then
        DepotLogger.info("_onInteractAction: open depot #%d", self._nearDepotId)
        self:openDialog(self._nearDepotId)
    end
end

function DepotManager:_onSiloFillConfirm(result)
    local ctx = self._pendingSiloFill
    self._pendingSiloFill = nil
    if not result or not ctx then return end

    DepotLogger.info("Silo fill confirmed: depot=%d silo=%d %s %.0fL farm=%d",
        ctx.depotId, ctx.siloId, ctx.fillTypeName, ctx.maxLiters, ctx.farmId)

    DepotSiloFillEvent.sendToServer(
        ctx.depotId, ctx.siloId,
        ctx.fillTypeName, ctx.fillTypeIndex, ctx.maxLiters, ctx.farmId)

    self.pendingOrders[ctx.farmId] = nil
    self:_updateInteractPrompt()
end

-- ─── Depot Proximity (on-foot player) ───────────────────

function DepotManager:_checkDepotProximity()
    if not next(self.depotNodes) then return end

    local px, pz
    if g_localPlayer and g_localPlayer.rootNode then
        local ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
        if ok and x then px, pz = x, z end
    end
    if not px then
        local cv = g_currentMission and g_currentMission.controlledVehicle
        if cv and cv.rootNode then
            local ok, x, y, z = pcall(getWorldTranslation, cv.rootNode)
            if ok and x then px, pz = x, z end
        end
    end

    if not px then
        if self._nearDepotId then
            self._nearDepotId = nil
            self:_updateInteractPrompt()
            self:closeDialog()
        end
        return
    end

    local nearId, nearDist = nil, PROXIMITY_THRESHOLD + 1
    for id, node in pairs(self.depotNodes) do
        if node then
            local ok, dx, dy, dz = pcall(getWorldTranslation, node)
            if ok and dx then
                local dist = math.sqrt((px - dx) ^ 2 + (pz - dz) ^ 2)
                if dist < PROXIMITY_THRESHOLD and dist < nearDist then
                    nearId, nearDist = id, dist
                end
            end
        end
    end

    if nearId ~= self._nearDepotId then
        local prev = self._nearDepotId
        self._nearDepotId = nearId
        if not nearId and prev then
            DepotLogger.info("Proximity: left depot #%d", prev)
            self:closeDialog()
        elseif nearId then
            DepotLogger.info("Proximity: entered depot #%d", nearId)
        end
        self:_updateInteractPrompt()
    end
end

-- ─── Silo Proximity ──────────────────────────────────────
-- On foot : sets _nearSiloId → shows E-key prompt → player presses E → YesNo.
-- In vehicle: auto-shows YesNo when vehicle pulls up (same pattern as depot sell).

function DepotManager:_checkSiloProximity()
    if not next(self.siloNodes) then return end

    local cv = g_currentMission and g_currentMission.controlledVehicle

    if cv then
        self:_checkSiloProximityVehicle(cv)
    else
        self:_checkSiloProximityOnFoot()
    end
end

function DepotManager:_checkSiloProximityVehicle(cv)
    -- Clear any on-foot silo state when the player gets in a vehicle
    if self._nearSiloId then
        self._nearSiloId = nil
        self:_updateInteractPrompt()
    end

    if not cv.rootNode then return end
    local ok, vx, vy, vz = pcall(getWorldTranslation, cv.rootNode)
    if not ok or not vx then return end

    local nearSiloId = nil
    for id, node in pairs(self.siloNodes) do
        if node then
            local nok, sx, sy, sz = pcall(getWorldTranslation, node)
            if nok and sx then
                local dist = math.sqrt((vx - sx) ^ 2 + (vz - sz) ^ 2)
                if dist <= SILO_VEHICLE_PROXIMITY then
                    nearSiloId = id
                    break
                end
            end
        end
    end

    if nearSiloId ~= self._nearVehicleSiloId then
        local prev = self._nearVehicleSiloId
        self._nearVehicleSiloId = nearSiloId
        if nearSiloId and not prev then
            DepotLogger.info("Silo proximity: vehicle entered silo #%d", nearSiloId)
            local farmId = g_localPlayer and g_localPlayer.farmId or 0
            local order = self.pendingOrders[farmId]
            if order and self._siloFillCooldown <= 0 then
                self:_tryShowSiloFillDialog(nearSiloId, farmId, order)
            end
        elseif not nearSiloId and prev then
            DepotLogger.info("Silo proximity: vehicle left silo #%d", prev)
        end
    end
end

function DepotManager:_checkSiloProximityOnFoot()
    -- Clear vehicle silo state when player exits vehicle
    if self._nearVehicleSiloId then
        self._nearVehicleSiloId = nil
    end

    local px, pz
    if g_localPlayer and g_localPlayer.rootNode then
        local ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
        if ok and x then px, pz = x, z end
    end

    if not px then
        if self._nearSiloId then
            self._nearSiloId = nil
            self:_updateInteractPrompt()
        end
        return
    end

    local nearSiloId = nil
    for id, node in pairs(self.siloNodes) do
        if node then
            local ok, sx, sy, sz = pcall(getWorldTranslation, node)
            if ok and sx then
                local dist = math.sqrt((px - sx) ^ 2 + (pz - sz) ^ 2)
                if dist <= PROXIMITY_THRESHOLD then
                    nearSiloId = id
                    break
                end
            end
        end
    end

    if nearSiloId ~= self._nearSiloId then
        local prev = self._nearSiloId
        self._nearSiloId = nearSiloId
        if nearSiloId then
            DepotLogger.info("Silo proximity: entered silo #%d (on foot)", nearSiloId)
        elseif prev then
            DepotLogger.info("Silo proximity: left silo #%d (on foot)", prev)
        end
        self:_updateInteractPrompt()
    elseif nearSiloId then
        self:_updateInteractPrompt()
    end
end

-- Shared: builds context and shows YesNo confirmation for silo fill.
-- Called from both the on-foot E-key path and the vehicle auto-trigger path.
function DepotManager:_tryShowSiloFillDialog(siloId, farmId, order)
    local depotId = order.depotId
    if not depotId or not self.depots[depotId] then
        depotId = next(self.depots)
    end
    if not depotId then
        DepotLogger.warning("Silo fill: no depot registered")
        return
    end

    self._pendingSiloFill = {
        depotId      = depotId,
        siloId       = siloId,
        fillTypeName = order.fillTypeName,
        fillTypeIndex= order.fillTypeIndex,
        maxLiters    = order.maxLiters,
        displayName  = order.displayName,
        farmId       = farmId,
    }

    self._siloFillCooldown = SILO_FILL_COOLDOWN

    local text = string.format(
        tr("fd_silo_fill_confirm", "Collect %.0fL of %s?\n\nYour vehicle will be filled."),
        order.maxLiters, order.displayName)
    YesNoDialog.show(DepotManager._onSiloFillConfirm, self, text)
end

-- ─── Pickup Zone Proximity (on-foot) ────────────────────

function DepotManager:_checkPickupProximity()
    if not next(self.pickupNodes) then return end
    -- Only relevant when on foot
    if g_currentMission and g_currentMission.controlledVehicle then
        if self._nearPickupId then
            self._nearPickupId = nil
            self:_updateInteractPrompt()
        end
        return
    end

    local px, pz
    if g_localPlayer and g_localPlayer.rootNode then
        local ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
        if ok and x then px, pz = x, z end
    end

    if not px then
        if self._nearPickupId then
            self._nearPickupId = nil
            self:_updateInteractPrompt()
        end
        return
    end

    local nearId = nil
    for id, node in pairs(self.pickupNodes) do
        if node then
            local ok, nx, ny, nz = pcall(getWorldTranslation, node)
            if ok and nx then
                local dist = math.sqrt((px - nx)^2 + (pz - nz)^2)
                if dist <= DepotConstants.DELIVERY.PROXIMITY_PICKUP then
                    nearId = id
                    break
                end
            end
        end
    end

    if nearId ~= self._nearPickupId then
        local prev = self._nearPickupId
        self._nearPickupId = nearId
        if nearId then
            DepotLogger.info("Pickup proximity: entered zone #%d", nearId)
        elseif prev then
            DepotLogger.info("Pickup proximity: left zone #%d", prev)
        end
        self:_updateInteractPrompt()
    elseif nearId then
        self:_updateInteractPrompt()
    end
end

function DepotManager:_tryShowDeliveryPickupDialog()
    local farmId = g_localPlayer and g_localPlayer.farmId or 0
    if not self.deliverySystem then return end

    -- Find a PENDING delivery for this farm across all depots
    local depotId, delivery = nil, nil
    for dId, rec in pairs(self.deliverySystem.deliveries) do
        if rec.farmId == farmId and rec.status == DeliverySystem.STATUS.PENDING then
            depotId  = dId
            delivery = rec
            break
        end
    end
    if not delivery then return end

    -- Client-side money pre-check — gives immediate feedback instead of silent server rejection
    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    if farm and farm:getBalance() < delivery.deliveryCost then
        if g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(
                tr("fd_depot_no_money", "Not enough money."), 3000)
        end
        return
    end

    self._pendingDeliveryPickup = { depotId = depotId, farmId = farmId }

    local costStr = g_i18n and g_i18n:formatMoney(delivery.deliveryCost, 0, true)
                   or string.format("$%.2f", delivery.deliveryCost)
    local text = string.format(
        tr("fd_delivery_pickup_confirm",
           "Collect delivery for %s?\n\nGoods will be stocked when you return to your depot."),
        costStr)
    YesNoDialog.show(DepotManager._onDeliveryPickupConfirm, self, text)
end

function DepotManager:_onDeliveryPickupConfirm(result)
    local ctx = self._pendingDeliveryPickup
    self._pendingDeliveryPickup = nil
    if not result or not ctx then return end
    DepotLogger.info("Delivery pickup confirmed: depot=%d farm=%d", ctx.depotId, ctx.farmId)
    DepotDeliveryPickupEvent.sendToServer(ctx.depotId, ctx.farmId)
end

-- ─── Vehicle at Depot Unload Trigger ─────────────────────

function DepotManager:_checkDepotVehicles()
    if not next(self.depotUnloadNodes) then return end

    local cv = g_currentMission and g_currentMission.controlledVehicle
    if not cv or not cv.rootNode then
        if self._nearUnloadDepotId then
            self._nearUnloadDepotId = nil
        end
        return
    end

    local ok, vx, vy, vz = pcall(getWorldTranslation, cv.rootNode)
    if not ok or not vx then return end

    local nearId = nil
    for id, node in pairs(self.depotUnloadNodes) do
        if node then
            local nok, nx, ny, nz = pcall(getWorldTranslation, node)
            if nok and nx then
                local dist = math.sqrt((vx - nx) ^ 2 + (vz - nz) ^ 2)
                if dist <= VEHICLE_UNLOAD_PROXIMITY then
                    nearId = id
                    break
                end
            end
        end
    end

    if nearId ~= self._nearUnloadDepotId then
        local prev = self._nearUnloadDepotId
        self._nearUnloadDepotId = nearId
        if nearId and not prev then
            DepotLogger.info("Vehicle entered depot #%d unload zone", nearId)
            if self._depotSellCooldown <= 0 then
                self:_tryShowDepotSellDialog(nearId, cv)
            end
        elseif not nearId and prev then
            DepotLogger.info("Vehicle left depot #%d unload zone", prev)
        end
    end
end

function DepotManager:_tryShowDepotSellDialog(depotId, vehicle)
    local found = findFertilizerInVehicle(vehicle, self.sfBridge)
    if not found then
        DepotLogger.info("Vehicle at depot #%d unload: no fertilizer found", depotId)
        return
    end

    local farmId = g_localPlayer and g_localPlayer.farmId or 0
    local revenue = self.pricing:calculateSellRevenue(found.fillTypeName, found.amount)
    local revenueStr = g_i18n and g_i18n:formatMoney(revenue, 0, true)
                       or string.format("$%.0f", revenue)

    self._pendingDepotSell = {
        depotId      = depotId,
        fillTypeName = found.fillTypeName,
        fillTypeIndex= found.fillTypeIndex,
        amount       = found.amount,
        farmId       = farmId,
    }

    local text = string.format(
        tr("fd_depot_sell_confirm", "Sell %.0fL of %s to depot for %s?"),
        found.amount, found.fillTypeName, revenueStr)

    DepotLogger.info("Showing depot sell dialog: %.0fL %s for farm %d",
        found.amount, found.fillTypeName, farmId)
    YesNoDialog.show(DepotManager._onDepotSellConfirm, self, text)
end

function DepotManager:_onDepotSellConfirm(result)
    local ctx = self._pendingDepotSell
    self._pendingDepotSell = nil
    self._depotSellCooldown = DEPOT_SELL_COOLDOWN

    if not result or not ctx then return end

    DepotLogger.info("Depot sell confirmed: %.0fL %s for farm %d",
        ctx.amount, ctx.fillTypeName, ctx.farmId)

    DepotSellEvent.sendToServer(
        ctx.depotId, ctx.fillTypeName, ctx.fillTypeIndex, ctx.amount, ctx.farmId)
end

-- ─── HUD ─────────────────────────────────────────────────

function DepotManager:drawHUD()
    if self.hud then self.hud:draw() end
end

-- ─── Console Commands ────────────────────────────────────

function DepotManager:cmdDebugDepot()
    DepotLogger._debug = not DepotLogger._debug
    return DepotConstants.LOG_PREFIX .. " Debug: " .. tostring(DepotLogger._debug)
end

local function _iterateDepots(manager, targetId, fn)
    local count = 0
    for id, placeable in pairs(manager.depots) do
        if targetId == nil or id == targetId then
            fn(id, placeable)
            count = count + 1
        end
    end
    return count
end

function DepotManager:cmdFDFillStock(depotIdArg)
    if not g_server then
        return DepotConstants.LOG_PREFIX .. " FDFillStock: server only"
    end
    local targetId = depotIdArg and tonumber(depotIdArg) or nil
    local fillTypes = self.sfBridge:getFillTypeList()
    local cap = self.settings.storageCapacity or DepotConstants.STORAGE_CAPACITY
    local depotCount = _iterateDepots(self, targetId, function(id, _)
        for _, ft in ipairs(fillTypes) do
            self.depotSystem:setStorageLevel(id, ft.name, cap)
        end
        self:broadcastSync(id)
        DepotLogger.info("FDFillStock: depot #%d filled (%d types, %.0fL each)", id, #fillTypes, cap)
    end)
    return string.format("%s FDFillStock: filled %d depot(s) to %.0fL each type",
        DepotConstants.LOG_PREFIX, depotCount, cap)
end

function DepotManager:cmdFDEmptyStock(depotIdArg)
    if not g_server then
        return DepotConstants.LOG_PREFIX .. " FDEmptyStock: server only"
    end
    local targetId = depotIdArg and tonumber(depotIdArg) or nil
    local fillTypes = self.sfBridge:getFillTypeList()
    local depotCount = _iterateDepots(self, targetId, function(id, _)
        for _, ft in ipairs(fillTypes) do
            self.depotSystem:setStorageLevel(id, ft.name, 0)
        end
        self:broadcastSync(id)
        DepotLogger.info("FDEmptyStock: depot #%d emptied", id)
    end)
    return string.format("%s FDEmptyStock: emptied %d depot(s)",
        DepotConstants.LOG_PREFIX, depotCount)
end

function DepotManager:cmdFDCancelDelivery(depotIdArg)
    if not g_server then
        return DepotConstants.LOG_PREFIX .. " FDCancelDelivery: server only"
    end
    if not self.deliverySystem then
        return DepotConstants.LOG_PREFIX .. " FDCancelDelivery: deliverySystem not initialized"
    end
    local targetId = depotIdArg and tonumber(depotIdArg) or nil
    if not targetId then
        return DepotConstants.LOG_PREFIX .. " FDCancelDelivery: usage: FDCancelDelivery <depotId>"
    end
    local rec = self.deliverySystem:getDelivery(targetId)
    if not rec then
        return string.format("%s FDCancelDelivery: no active delivery for depot #%d",
            DepotConstants.LOG_PREFIX, targetId)
    end
    local farmId = rec.farmId
    local ok, penalty = self.deliverySystem:cancelDelivery(targetId, farmId)
    if ok then
        DepotDeliverySyncEvent.broadcast(targetId)
        return string.format("%s FDCancelDelivery: depot #%d cancelled (penalty=$%.2f)",
            DepotConstants.LOG_PREFIX, targetId, penalty or 0)
    end
    return DepotConstants.LOG_PREFIX .. " FDCancelDelivery: failed"
end
