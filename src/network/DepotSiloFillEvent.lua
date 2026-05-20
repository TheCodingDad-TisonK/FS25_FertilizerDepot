-- =========================================================
-- FS25 Fertilizer Depot - Silo Fill Network Event
-- =========================================================
-- Client fires when player activates the silo fill prompt.
-- Server executes buyFromSilo (vehicle search at silo position).

DepotSiloFillEvent = {}
DepotSiloFillEvent.typeName = "DepotSiloFillEvent"
local DepotSiloFillEvent_mt = Class(DepotSiloFillEvent, Event)

function DepotSiloFillEvent.emptyNew()
    return Event.new(setmetatable({}, DepotSiloFillEvent_mt))
end

function DepotSiloFillEvent.new(depotId, siloId, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    local self = Event.new(setmetatable({}, DepotSiloFillEvent_mt))
    self.depotId        = depotId
    self.siloId         = siloId
    self.fillTypeName   = fillTypeName
    self.fillTypeIndex  = fillTypeIndex
    self.requestedLiters = requestedLiters
    self.farmId         = farmId
    return self
end

function DepotSiloFillEvent:readStream(streamId, connection)
    self.depotId         = streamReadInt32(streamId)
    self.siloId          = streamReadInt32(streamId)
    self.fillTypeName    = streamReadString(streamId)
    self.fillTypeIndex   = streamReadInt32(streamId)
    self.requestedLiters = streamReadFloat32(streamId)
    self.farmId          = streamReadUInt8(streamId)
end

function DepotSiloFillEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.depotId or 0)
    streamWriteInt32(streamId, self.siloId or 0)
    streamWriteString(streamId, self.fillTypeName or "")
    streamWriteInt32(streamId, self.fillTypeIndex or 0)
    streamWriteFloat32(streamId, self.requestedLiters or 0)
    streamWriteUInt8(streamId, self.farmId or 1)
end

function DepotSiloFillEvent:run(connection)
    if not g_server or not g_DepotManager then return end

    local siloNode = g_DepotManager.siloNodes[self.siloId]
    local ok, msgKey, liters = g_DepotManager.depotSystem:buyFromSilo(
        self.depotId, siloNode,
        self.fillTypeName, self.fillTypeIndex,
        self.requestedLiters, self.farmId)

    DepotLogger.info("DepotSiloFillEvent:run depot=%d silo=%d %s %.0fL farm=%d siloNode=%s",
        self.depotId, self.siloId, self.fillTypeName, self.requestedLiters, self.farmId,
        tostring(siloNode))
    if ok and liters > 0 then
        g_DepotManager:broadcastSync(self.depotId)
        g_DepotManager:clearPendingOrder(self.farmId)
        DepotLogger.info("Silo fill SUCCESS: %.0fL %s for farm %d", liters, self.fillTypeName, self.farmId)
    else
        DepotLogger.warning("Silo fill FAILED: %s (depot=%d silo=%d type=%s)",
            tostring(msgKey), self.depotId, self.siloId, self.fillTypeName)
    end
end

function DepotSiloFillEvent.sendToServer(depotId, siloId, fillTypeName, fillTypeIndex, requestedLiters, farmId)
    if g_client then
        g_client:getServerConnection():sendEvent(
            DepotSiloFillEvent.new(depotId, siloId, fillTypeName, fillTypeIndex, requestedLiters, farmId))
    end
end
