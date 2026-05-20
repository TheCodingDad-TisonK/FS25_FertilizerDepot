-- =========================================================
-- FS25 Fertilizer Depot - Manager Singleton
-- =========================================================
-- Set as g_DepotManager via getfenv(0) during Mission00.load.
-- Owns all subsystems and handles Mission00 lifecycle hooks.

local _depotMgrModName = g_currentModName

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[_depotMgrModName]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

---@class DepotManager
DepotManager = {}
local DepotManager_mt = Class(DepotManager)

local PROXIMITY_THRESHOLD = 8.0  -- meters, on-foot interaction radius

function DepotManager.new()
    local self = setmetatable({}, DepotManager_mt)
    self.settings     = DepotSettings.new()
    self.sfBridge     = SoilFertilizerBridge.new()
    self.pricing      = DepotPricing.new(self.sfBridge)
    self.depotSystem  = DepotSystem.new(self.pricing)
    self.depots       = {}    -- public: [depotId] = PlaceableDepot instance
    self.depotNodes   = {}    -- [depotId] = world-position node for proximity check
    self.activeDialog = nil   -- currently open DepotDialog (if any)
    self._initialized      = false
    self._nearDepotId      = nil   -- depot we're currently near
    self._nearActionEventId = nil  -- registered F-key action event
    self._proximityTimer   = 0     -- ms accumulator for 500ms polling
    self._settingsEventId  = nil   -- Shift+D event ID (set by main.lua hook)
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
    self.sfBridge:invalidateCache()
    DepotLogger.info("DepotManager deleted")
end

-- ─── Depot Registration ──────────────────────────────────

-- Called by PlaceableDepot:onFinalizePlacement
function DepotManager:registerDepot(placeableDepot)
    local id = self.depotSystem:registerDepot()
    self.depots[id] = placeableDepot
    placeableDepot.depotId = id

    -- Store the interaction-point node for proximity detection.
    -- Use playerTriggerNode (entrance) if available, fall back to root.
    local spec = placeableDepot[PlaceableDepot.SPEC_TABLE_NAME]
    self.depotNodes[id] = (spec and spec.playerTriggerNode) or placeableDepot.rootNode

    DepotLogger.info("Depot #%d registered (node: %s)", id,
        tostring(self.depotNodes[id]))
    return id
end

-- Called by PlaceableDepot:onDelete
function DepotManager:unregisterDepot(depotId)
    self.depotSystem:unregisterDepot(depotId)
    self.depots[depotId] = nil
    self.depotNodes[depotId] = nil
    if self._nearDepotId == depotId then
        self:_leaveDepotProximity()
    end
    DepotLogger.info("Depot #%d unregistered", depotId)
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

-- ─── Settings Dialog ─────────────────────────────────────

function DepotManager:openSettingsDialog()
    DepotSettingsDialog.show()
end

-- ─── Proximity Detection (replaces addTrigger) ───────────
-- Polled every 500ms from FSBaseMission.update.
-- Registers/removes ACTIVATE_HANDTOOL (F key) based on
-- on-foot player distance to depot entrance node.

function DepotManager:update(dt)
    self._proximityTimer = self._proximityTimer + dt
    if self._proximityTimer < 500 then return end
    self._proximityTimer = 0
    self:_checkProximity()
end

function DepotManager:_checkProximity()
    -- One-shot diagnostic on first run after depot is registered
    if not self._proximityDiagDone and next(self.depotNodes) then
        self._proximityDiagDone = true
        local hasPlayer = g_localPlayer ~= nil
        local hasNode   = g_localPlayer and g_localPlayer.rootNode ~= nil
        local depotNode = next(self.depotNodes) and select(2, next(self.depotNodes))
        local depotOk, dx, dy, dz = false, 0, 0, 0
        if depotNode then
            depotOk, dx, dy, dz = pcall(getWorldTranslation, depotNode)
        end
        DepotLogger.info("Proximity diag: g_localPlayer=%s rootNode=%s depotNode=%s depotPos=%s,%.1f,%.1f,%.1f",
            tostring(hasPlayer), tostring(hasNode), tostring(depotNode),
            tostring(depotOk), dx, dy, dz)
    end

    -- Get local player position.
    -- Try g_localPlayer first; fall back to controlled vehicle position.
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

    -- Find nearest depot within threshold
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
        else
            DepotLogger.warning("Proximity: ACTIVATE_HANDTOOL registration failed for depot #%d", depotId)
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
