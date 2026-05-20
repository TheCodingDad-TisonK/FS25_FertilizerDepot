-- =========================================================
-- FS25 Fertilizer Depot - Manager Singleton
-- =========================================================
-- Set as g_DepotManager via getfenv(0) during Mission00.load.
-- Owns all subsystems and handles Mission00 lifecycle hooks.

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
    if self.activeDialog then
        g_gui:closeDialog(self.activeDialog)
        self.activeDialog = nil
    end
    DepotDialog.show(depotId)
    self.activeDialog = DepotDialog.INSTANCE
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
    -- Skip if player is controlling a vehicle (depot is walk-in only)
    if g_currentMission and g_currentMission.controlledVehicle then
        if self._nearDepotId then self:_leaveDepotProximity() end
        return
    end

    -- Get local player position
    local px, pz
    if g_localPlayer and g_localPlayer.rootNode then
        local ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
        if ok and x then px, pz = x, z end
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
            g_inputBinding:setActionEventText(evId, g_i18n:getText("fd_depot_open_action"))
            g_inputBinding:setActionEventActive(evId, true)
            DepotLogger.debug("Proximity: entered depot #%d range", depotId)
        else
            DepotLogger.warning("Proximity: failed to register ACTIVATE_HANDTOOL for depot #%d", depotId)
        end
    end
end

function DepotManager:_leaveDepotProximity()
    if self._nearActionEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self._nearActionEventId)
        self._nearActionEventId = nil
    end
    DepotLogger.debug("Proximity: left depot #%s range", tostring(self._nearDepotId))
    self._nearDepotId = nil
    self:closeDialog()
end

function DepotManager:_onInteractAction()
    if self._nearDepotId then
        self:openDialog(self._nearDepotId)
    end
end
