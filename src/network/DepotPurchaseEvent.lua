-- =========================================================
-- FS25 Fertilizer Depot - Purchase Event (Client -> Server)
-- =========================================================

---@class DepotPurchaseEvent
DepotPurchaseEvent = {}
DepotPurchaseEvent_mt = Class(DepotPurchaseEvent, Event)

InitEventClass(DepotPurchaseEvent, "DepotPurchaseEvent")

function DepotPurchaseEvent.emptyNew()
    local self = Event.new(DepotPurchaseEvent_mt)
    return self
end

function DepotPurchaseEvent.new(depotId, fillTypeName, fillTypeIndex, liters, farmId)
    local self = DepotPurchaseEvent.emptyNew()
    self.depotId       = depotId
    self.fillTypeName  = fillTypeName
    self.fillTypeIndex = fillTypeIndex
    self.liters        = liters
    self.farmId        = farmId
    return self
end

function DepotPurchaseEvent:readStream(streamId, connection)
    self.depotId       = streamReadInt32(streamId)
    self.fillTypeName  = streamReadString(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self.liters        = streamReadFloat32(streamId)
    self.farmId        = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotPurchaseEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,  self.depotId)
    streamWriteString(streamId, self.fillTypeName)
    streamWriteInt32(streamId,  self.fillTypeIndex)
    streamWriteFloat32(streamId, self.liters)
    streamWriteUInt8(streamId,  self.farmId)
end

function DepotPurchaseEvent:run(connection)
    if not g_server then return end
    if not g_DepotManager then return end

    local success, msgKey, actualLiters = g_DepotManager.depotSystem:buyFillType(
        self.depotId, self.fillTypeName, self.fillTypeIndex, self.liters, self.farmId)

    if success then
        g_DepotManager:broadcastSync(self.depotId)
    end
end

function DepotPurchaseEvent.sendToServer(depotId, fillTypeName, fillTypeIndex, liters, farmId)
    local evt = DepotPurchaseEvent.new(depotId, fillTypeName, fillTypeIndex, liters, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
