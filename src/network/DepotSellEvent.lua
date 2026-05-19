-- =========================================================
-- FS25 Fertilizer Depot - Sell Event (Client -> Server)
-- =========================================================

---@class DepotSellEvent
DepotSellEvent = {}
DepotSellEvent_mt = Class(DepotSellEvent, Event)

InitEventClass(DepotSellEvent, "DepotSellEvent")

function DepotSellEvent.emptyNew()
    local self = Event.new(DepotSellEvent_mt)
    return self
end

function DepotSellEvent.new(depotId, fillTypeName, fillTypeIndex, liters, farmId)
    local self = DepotSellEvent.emptyNew()
    self.depotId       = depotId
    self.fillTypeName  = fillTypeName
    self.fillTypeIndex = fillTypeIndex
    self.liters        = liters
    self.farmId        = farmId
    return self
end

function DepotSellEvent:readStream(streamId, connection)
    self.depotId       = streamReadInt32(streamId)
    self.fillTypeName  = streamReadString(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self.liters        = streamReadFloat32(streamId)
    self.farmId        = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotSellEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,  self.depotId)
    streamWriteString(streamId, self.fillTypeName)
    streamWriteInt32(streamId,  self.fillTypeIndex)
    streamWriteFloat32(streamId, self.liters)
    streamWriteUInt8(streamId,  self.farmId)
end

function DepotSellEvent:run(connection)
    if not g_server then return end
    if not g_DepotManager then return end

    local success, msgKey, liters, revenue = g_DepotManager.depotSystem:sellFillType(
        self.depotId, self.fillTypeName, self.fillTypeIndex, self.liters, self.farmId)

    if success then
        g_DepotManager:broadcastSync(self.depotId)
    end
end

function DepotSellEvent.sendToServer(depotId, fillTypeName, fillTypeIndex, liters, farmId)
    local evt = DepotSellEvent.new(depotId, fillTypeName, fillTypeIndex, liters, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
