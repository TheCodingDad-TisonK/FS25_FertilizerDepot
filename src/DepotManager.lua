-- =========================================================
-- FS25 Fertilizer Depot - Manager Singleton
-- =========================================================
-- Set as g_DepotManager via getfenv(0) during Mission00.load.
-- Owns all subsystems and handles Mission00 lifecycle hooks.

---@class DepotManager
DepotManager = {}
local DepotManager_mt = Class(DepotManager)

function DepotManager.new()
    local self = setmetatable({}, DepotManager_mt)
    self.sfBridge     = SoilFertilizerBridge.new()
    self.pricing      = DepotPricing.new(self.sfBridge)
    self.depotSystem  = DepotSystem.new(self.pricing)
    self.depots       = {}   -- public: [depotId] = PlaceableDepot instance
    self.activeDialog = nil  -- currently open DepotDialog (if any)
    self._initialized = false
    return self
end

function DepotManager:initialize()
    if self._initialized then return end
    self._initialized = true
    DepotLogger.info("DepotManager initialized (SF installed: %s)",
        tostring(self.sfBridge:isInstalled()))
end

function DepotManager:delete()
    -- Close any open dialog
    if self.activeDialog then
        self.activeDialog:close()
        self.activeDialog = nil
    end
    -- Invalidate bridge cache
    self.sfBridge:invalidateCache()
    DepotLogger.info("DepotManager deleted")
end

-- ─── Depot Registration ──────────────────────────────────

-- Called by PlaceableDepot:onFinalizePlacement
function DepotManager:registerDepot(placeableDepot)
    local id = self.depotSystem:registerDepot()
    self.depots[id] = placeableDepot
    placeableDepot.depotId = id
    DepotLogger.info("Depot #%d registered", id)
    return id
end

-- Called by PlaceableDepot:onDelete
function DepotManager:unregisterDepot(depotId)
    self.depotSystem:unregisterDepot(depotId)
    self.depots[depotId] = nil
    DepotLogger.info("Depot #%d unregistered", depotId)
end

-- ─── Network Helpers ─────────────────────────────────────

-- Broadcast current depot storage state to all clients.
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

-- ─── Per-Frame Update ────────────────────────────────────

function DepotManager:update(dt)
    -- Reserved for future timed logic (e.g. price fluctuation animations)
end
