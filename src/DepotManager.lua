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

local PROXIMITY_THRESHOLD = 8.0   -- metres, on-foot radius
local SILO_FILL_COOLDOWN  = 2000  -- ms between silo fill triggers

function DepotManager.new()
    local self = setmetatable({}, DepotManager_mt)
    self.settings     = DepotSettings.new()
    self.sfBridge     = SoilFertilizerBridge.new()
    self.pricing      = DepotPricing.new(self.sfBridge)
    self.depotSystem  = DepotSystem.new(self.pricing)

    self.depots       = {}
    self.depotNodes   = {}
    self.silos        = {}
    self.siloNodes    = {}
    self._nextSiloId  = 1

    self.pendingOrders = {}
    self.activeDialog  = nil

    self._initialized     = false
    self._nearDepotId     = nil
    self._nearSiloId      = nil
    self._proximityTimer  = 0
    self._settingsEventId = nil

    -- Single persistent ACTIVATE_HANDTOOL event (shared for depot + silo)
    self._interactEventId     = nil
    self._siloFillCooldown    = 0

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
    DepotLogger.info("Depot #%d registered (node: %s)", id, tostring(self.depotNodes[id]))
    return id
end

function DepotManager:unregisterDepot(depotId)
    self.depotSystem:unregisterDepot(depotId)
    self.depots[depotId] = nil
    self.depotNodes[depotId] = nil
    if self._nearDepotId == depotId then
        self._nearDepotId = nil
        self:_updateInteractPrompt()
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
        self._nearSiloId = nil
        self:_updateInteractPrompt()
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
    -- Refresh prompt in case player is already near silo
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
    -- Tick silo fill cooldown
    if self._siloFillCooldown > 0 then
        self._siloFillCooldown = self._siloFillCooldown - dt
    end

    self._proximityTimer = self._proximityTimer + dt
    if self._proximityTimer < 500 then return end
    self._proximityTimer = 0
    self:_checkProximity()
    self:_checkSiloVehicles()
end

-- ─── Single Persistent Interact Action ───────────────────
-- One ACTIVATE_HANDTOOL registration, shared for depot open + silo fill.
-- Active/visible is toggled; the callback checks _nearDepotId / _nearSiloId.

function DepotManager:_getOrRegisterInteractEvent()
    if self._interactEventId then return self._interactEventId end
    if not g_inputBinding then return nil end

    local ok, evId = g_inputBinding:registerActionEvent(
        InputAction.ACTIVATE_HANDTOOL, self,
        DepotManager._onInteractAction, false, true, false, true)
    if ok and evId then
        self._interactEventId = evId
        g_inputBinding:setActionEventTextVisibility(evId, false)
        g_inputBinding:setActionEventActive(evId, false)
        DepotLogger.info("ACTIVATE_HANDTOOL registered (id=%s)", tostring(evId))
    end
    return self._interactEventId
end

function DepotManager:_updateInteractPrompt()
    local evId = self:_getOrRegisterInteractEvent()
    if not evId or not g_inputBinding then return end

    local farmId = g_localPlayer and g_localPlayer.farmId or 0

    -- Silo takes priority when near silo with a pending order
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
            -- Near silo but no order — show hint to go to depot first
            g_inputBinding:setActionEventText(evId,
                tr("fd_silo_no_order", "No pending order. Go to Depot first."))
            g_inputBinding:setActionEventTextVisibility(evId, true)
            g_inputBinding:setActionEventActive(evId, false)
            return
        end
    end

    -- Depot interaction
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
    -- Silo fill
    if self._nearSiloId then
        if self._siloFillCooldown > 0 then return end  -- debounce

        local farmId = g_localPlayer and g_localPlayer.farmId or 0
        local order = self.pendingOrders[farmId]
        if not order then return end

        local depotId = order.depotId
        if not depotId or not self.depots[depotId] then
            depotId = next(self.depots)
        end
        if not depotId then
            DepotLogger.warning("Silo fill: no depot registered")
            return
        end

        self._siloFillCooldown = SILO_FILL_COOLDOWN
        DepotLogger.info("Silo fill: depot=%d silo=%d %s %.0fL farm=%d",
            depotId, self._nearSiloId, order.fillTypeName, order.maxLiters, farmId)

        DepotSiloFillEvent.sendToServer(
            depotId, self._nearSiloId,
            order.fillTypeName, order.fillTypeIndex, order.maxLiters, farmId)

        self.pendingOrders[farmId] = nil
        self:_updateInteractPrompt()
        return
    end

    -- Depot open
    if self._nearDepotId then
        DepotLogger.info("_onInteractAction: open depot #%d", self._nearDepotId)
        self:openDialog(self._nearDepotId)
    end
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

-- ─── Silo Proximity (on-foot player, must not be in vehicle) ─────────────

function DepotManager:_checkSiloVehicles()
    if not next(self.siloNodes) then return end

    -- Only detect when player is ON FOOT (not seated in a vehicle).
    -- ACTIVATE_HANDTOOL only fires reliably in on-foot context.
    if g_currentMission and g_currentMission.controlledVehicle then
        if self._nearSiloId then
            self._nearSiloId = nil
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
            DepotLogger.info("Silo proximity: entered silo #%d", nearSiloId)
        elseif prev then
            DepotLogger.info("Silo proximity: left silo #%d", prev)
        end
        self:_updateInteractPrompt()
    elseif nearSiloId then
        -- Refresh prompt in case order state changed while already near silo
        self:_updateInteractPrompt()
    end
end
