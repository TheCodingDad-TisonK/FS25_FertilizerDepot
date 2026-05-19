-- =========================================================
-- FS25 Fertilizer Depot - Sync Event (Server -> Clients)
-- =========================================================
-- Sends full storage state for one depot to all clients (or one joining client).

---@class DepotSyncEvent
DepotSyncEvent = {}
DepotSyncEvent_mt = Class(DepotSyncEvent, Event)

InitEventClass(DepotSyncEvent, "DepotSyncEvent")

function DepotSyncEvent.emptyNew()
    local self = Event.new(DepotSyncEvent_mt)
    return self
end

-- storageTable: {[fillTypeName] = liters, ...}
function DepotSyncEvent.new(depotId, storageTable)
    local self = DepotSyncEvent.emptyNew()
    self.depotId      = depotId
    self.storageTable = storageTable or {}
    return self
end

function DepotSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.depotId)
    -- Count entries first (stream length must be known ahead)
    local count = 0
    for _ in pairs(self.storageTable) do count = count + 1 end
    streamWriteUInt16(streamId, count)
    for name, liters in pairs(self.storageTable) do
        streamWriteString(streamId, name)
        streamWriteFloat32(streamId, liters)
    end
end

function DepotSyncEvent:readStream(streamId, connection)
    self.depotId = streamReadInt32(streamId)
    local count  = streamReadUInt16(streamId)
    self.storageTable = {}
    for _ = 1, count do
        local name  = streamReadString(streamId)
        local liters = streamReadFloat32(streamId)
        self.storageTable[name] = liters
    end
    self:run(connection)
end

function DepotSyncEvent:run(connection)
    -- Client-side: update local depot state
    if g_server then return end
    if not g_DepotManager then return end
    local system = g_DepotManager.depotSystem
    local depot = system:getDepot(self.depotId)
    if not depot then return end
    -- Apply incoming storage levels
    for name, liters in pairs(self.storageTable) do
        depot.storageLevel[name] = liters
    end
    -- Notify any open dialog to refresh
    if g_DepotManager.activeDialog then
        g_DepotManager.activeDialog:onSyncReceived(self.depotId)
    end
end

-- Server utility: broadcast current storage state for depotId to all clients.
function DepotSyncEvent.broadcast(depotId)
    if not g_server then return end
    if not g_DepotManager then return end
    local system = g_DepotManager.depotSystem
    local depot  = system:getDepot(depotId)
    if not depot then return end
    local evt = DepotSyncEvent.new(depotId, depot.storageLevel)
    g_server:broadcastEvent(evt)
end
