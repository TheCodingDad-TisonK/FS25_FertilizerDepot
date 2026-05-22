-- =========================================================
-- FS25 Fertilizer Depot - Delivery Cancel Event (Client -> Server)
-- =========================================================

---@class DepotDeliveryCancelEvent
DepotDeliveryCancelEvent = {}
DepotDeliveryCancelEvent_mt = Class(DepotDeliveryCancelEvent, Event)

InitEventClass(DepotDeliveryCancelEvent, "DepotDeliveryCancelEvent")

function DepotDeliveryCancelEvent.emptyNew()
    return Event.new(DepotDeliveryCancelEvent_mt)
end

function DepotDeliveryCancelEvent.new(depotId, farmId)
    local self = DepotDeliveryCancelEvent.emptyNew()
    self.depotId = depotId
    self.farmId  = farmId
    return self
end

function DepotDeliveryCancelEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.depotId or 0)
    streamWriteUInt8(streamId,  self.farmId  or 1)
end

function DepotDeliveryCancelEvent:readStream(streamId, connection)
    self.depotId = streamReadInt32(streamId)
    self.farmId  = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotDeliveryCancelEvent:run(connection)
    if not g_server or not g_DepotManager then return end
    local ds = g_DepotManager.deliverySystem
    if not ds then return end

    local ok, penalty = ds:cancelDelivery(self.depotId, self.farmId)
    if ok then
        DepotDeliverySyncEvent.broadcast(self.depotId)
        DepotLogger.info("Delivery cancelled broadcast sent: depot=%d penalty=$%.2f",
            self.depotId, penalty or 0)
    else
        DepotLogger.warning("DeliveryCancel rejected: depot=%d farm=%d reason=%s",
            self.depotId, self.farmId, tostring(penalty))
    end
end

function DepotDeliveryCancelEvent.sendToServer(depotId, farmId)
    local evt = DepotDeliveryCancelEvent.new(depotId, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
