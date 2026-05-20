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

---@class DepotManager
DepotManager = {}
local DepotManager_mt = Class(DepotManager)

local PROXIMITY_THRESHOLD  = 8.0   -- metres, on-foot depot trigger radius
local SILO_VEHICLE_RADIUS  = 20.0  -- metres, vehicle-at-silo detection radius

function DepotManager.new()
    local self = setmetatable({}, DepotManager_mt)
    self.settings     = DepotSettings.new()
    self.sfBridge     = SoilFertilizerBridge.new()
    self.pricing      = DepotPricing.new(self.sfBridge)
    self.depotSystem  = DepotSystem.new(self.pricing)

    -- Depot tracking
    self.depots       = {}    -- [depotId]  = PlaceableDepot instance
    self.depotNodes   = {}    -- [depotId]  = world-position node for proximity check

    -- Silo tracking
    self.silos        = {}    -- [siloId]   = PlaceableSilo instance
    self.siloNodes    = {}    -- [siloId]   = world-position node (rootNode)
    self._nextSiloId  = 1

    -- Pending pre-orders: [farmId] = {depotId, fillTypeName, fillTypeIndex, maxLiters, displayName}
    self.pendingOrders = {}

    self.activeDialog = nil

    self._initialized         = false
    self._nearDepotId         = nil
    self._nearActionEventId   = nil
    self._proximityTimer      = 0
    self._settingsEventId     = nil

    self._nearSiloId          = nil
    self._nearSiloActionEventId = nil

    return self
end

function DepotManager:initialize()
    if self._initialized then return end
    self._initialized = true
    DepotLogger.info("DepotManager initialized (SF installed: %s)",
        tostring(self.sfBridge:isInstalled()))
end

function DepotManager:delete()
    if self.activeDialog then
        self.activeDialog:close()
        self.activeDialog = nil
    end
    if self._nearActionEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self._nearActionEventId)
        self._nearActionEventId = nil
    end
    if self._nearSiloActionEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self._nearSiloActionEventId)
        self._nearSiloActionEventId = nil
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
    DepotLogger.info("Depot #%d registered (node: %s)", id, tostring(self.depotNodes[id]))
    return id
end

function DepotManager:unregisterDepot(depotId)
    self.depotSystem:unregisterDepot(depotId)
    self.depots[depotId] = nil
    self.depotNodes[depotId] = nil
    if self._nearDepotId == depotId then
        self:_leaveDepotProximity()
    end
    DepotLogger.info("Depot #%d unregistered", depotId)
end

-- ─── Silo Registration ───────────────────────────────────

function DepotManager:registerSilo(placeableSilo)
    local id = self._nextSiloId
    self._nextSiloId = self._nextSiloId + 1
    self.silos[id] = placeableSilo
    self.siloNodes[id] = placeableSilo.rootNode
    DepotLogger.info("Silo #%d registered (node: %s)", id, tostring(placeableSilo.rootNode))
    return id
end

function DepotManager:unregisterSilo(siloId)
    self.silos[siloId] = nil
    self.siloNodes[siloId] = nil
    if self._nearSiloId == siloId then
        self:_leaveSiloProximity()
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
    DepotLogger.info("Pending order set for farm %d: %s %.0fL", farmId, fillTypeName, maxLiters)
end

function DepotManager:getPendingOrder(farmId)
    return self.pendingOrders[farmId]
end

function DepotManager:clearPendingOrder(farmId)
    self.pendingOrders[farmId] = nil
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
    self._proximityTimer = self._proximityTimer + dt
    if self._proximityTimer < 500 then return end
    self._proximityTimer = 0
    self:_checkProximity()
    self:_checkSiloVehicles()
end

-- ─── Depot Proximity (on-foot player) ────────────────────

function DepotManager:_checkProximity()
    if not self._proximityDiagDone and next(self.depotNodes) then
        self._proximityDiagDone = true
        local hasPlayer = g_localPlayer ~= nil
        local hasNode   = g_localPlayer and g_localPlayer.rootNode ~= nil
        local depotNode = next(self.depotNodes) and select(2, next(self.depotNodes))
        local depotOk, dx, dy, dz = false, 0, 0, 0
        if depotNode then depotOk, dx, dy, dz = pcall(getWorldTranslation, depotNode) end
        DepotLogger.info("Proximity diag: g_localPlayer=%s rootNode=%s depotNode=%s depotPos=%s,%.1f,%.1f,%.1f",
            tostring(hasPlayer), tostring(hasNode), tostring(depotNode),
            tostring(depotOk), dx, dy, dz)
    end

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
        if self._nearDepotId then self:_leaveDepotProximity() end
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
        if self._nearDepotId then self:_leaveDepotProximity() end
        if nearId then self:_enterDepotProximity(nearId) end
    end
end

function DepotManager:_enterDepotProximity(depotId)
    self._nearDepotId = depotId
    if g_inputBinding then
        local ok, evId = g_inputBinding:registerActionEvent(
            InputAction.ACTIVATE_HANDTOOL, self,
            DepotManager._onInteractAction, false, true, false, true)
        if ok then
            self._nearActionEventId = evId
            g_inputBinding:setActionEventText(evId, tr("fd_depot_open_action", "Open Fertilizer Depot"))
            g_inputBinding:setActionEventTextVisibility(evId, true)
            g_inputBinding:setActionEventActive(evId, true)
            DepotLogger.info("Proximity: entered depot #%d", depotId)
        end
    end
end

function DepotManager:_leaveDepotProximity()
    if self._nearActionEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self._nearActionEventId)
        self._nearActionEventId = nil
    end
    DepotLogger.info("Proximity: left depot #%s", tostring(self._nearDepotId))
    self._nearDepotId = nil
    self:closeDialog()
end

function DepotManager:_onInteractAction()
    DepotLogger.info("_onInteractAction fired, nearDepotId=%s", tostring(self._nearDepotId))
    if self._nearDepotId then
        self:openDialog(self._nearDepotId)
    end
end

-- ─── Silo Proximity (on-foot player, same pattern as depot) ──────────────
-- Player parks vehicle near silo, exits, walks to silo, presses E.
-- buyFromSilo then searches for the parked vehicle within 60m of silo.

function DepotManager:_checkSiloVehicles()
    if not next(self.siloNodes) then return end

    -- ACTIVATE_HANDTOOL only fires on foot — check player position, not vehicle
    local px, pz
    if g_localPlayer and g_localPlayer.rootNode then
        local ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
        if ok and x then px, pz = x, z end
    end

    if not px then
        if self._nearSiloId then self:_leaveSiloProximity() end
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
        if self._nearSiloId then self:_leaveSiloProximity() end
        if nearSiloId then
            local farmId = g_localPlayer and g_localPlayer.farmId or 0
            self:_enterSiloProximity(nearSiloId, farmId)
        end
    elseif nearSiloId and not self._nearSiloActionEventId then
        -- Order might have been set while already standing near silo
        local farmId = g_localPlayer and g_localPlayer.farmId or 0
        self:_enterSiloProximity(nearSiloId, farmId)
    end
end

function DepotManager:_enterSiloProximity(siloId, farmId)
    self._nearSiloId = siloId
    local order = self.pendingOrders[farmId]
    if not order then
        DepotLogger.debug("Near silo #%d but no pending order for farm %d", siloId, farmId)
        return
    end

    if not g_inputBinding then return end
    local label = string.format(
        tr("fd_silo_collect_action", "Collect %s (%.0fL)"),
        order.displayName, order.maxLiters)

    local ok, evId = g_inputBinding:registerActionEvent(
        InputAction.ACTIVATE_HANDTOOL, self,
        DepotManager._onSiloFillAction, false, true, false, true)
    if ok then
        self._nearSiloActionEventId = evId
        g_inputBinding:setActionEventText(evId, label)
        g_inputBinding:setActionEventTextVisibility(evId, true)
        g_inputBinding:setActionEventActive(evId, true)
        DepotLogger.info("Silo proximity: silo #%d, order %s %.0fL",
            siloId, order.fillTypeName, order.maxLiters)
    end
end

function DepotManager:_leaveSiloProximity()
    if self._nearSiloActionEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self._nearSiloActionEventId)
        self._nearSiloActionEventId = nil
    end
    self._nearSiloId = nil
end

function DepotManager:_onSiloFillAction()
    DepotLogger.info("_onSiloFillAction fired, nearSiloId=%s", tostring(self._nearSiloId))
    local player = g_localPlayer
    if not player then return end
    local farmId = player.farmId or 0
    local order = self.pendingOrders[farmId]
    if not order or not self._nearSiloId then
        DepotLogger.warning("_onSiloFillAction: no order (farm=%d) or no nearSiloId", farmId)
        return
    end

    -- Find nearest depot (use order.depotId preferably)
    local depotId = order.depotId
    if not depotId or not self.depots[depotId] then
        depotId = next(self.depots)
    end
    if not depotId then
        DepotLogger.warning("Silo fill: no depot registered")
        return
    end

    DepotLogger.info("Silo fill: sending event depot=%d silo=%d %s %.0fL farm=%d",
        depotId, self._nearSiloId, order.fillTypeName, order.maxLiters, farmId)

    DepotSiloFillEvent.sendToServer(
        depotId, self._nearSiloId,
        order.fillTypeName, order.fillTypeIndex, order.maxLiters, farmId)

    -- Optimistically clear on client so prompt disappears immediately
    self.pendingOrders[farmId] = nil
    self:_leaveSiloProximity()
end
