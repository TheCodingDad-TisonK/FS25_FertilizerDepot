-- =========================================================
-- FS25 Fertilizer Depot - Delivery Order Event (Client -> Server)
-- =========================================================

---@class DepotDeliveryOrderEvent
DepotDeliveryOrderEvent = {}
DepotDeliveryOrderEvent_mt = Class(DepotDeliveryOrderEvent, Event)

InitEventClass(DepotDeliveryOrderEvent, "DepotDeliveryOrderEvent")

function DepotDeliveryOrderEvent.emptyNew()
    return Event.new(DepotDeliveryOrderEvent_mt)
end

function DepotDeliveryOrderEvent.new(depotId, farmId)
    local self = DepotDeliveryOrderEvent.emptyNew()
    self.depotId = depotId
    self.farmId  = farmId
    return self
end

function DepotDeliveryOrderEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.depotId or 0)
    streamWriteUInt8(streamId,  self.farmId  or 1)
end

function DepotDeliveryOrderEvent:readStream(streamId, connection)
    self.depotId = streamReadInt32(streamId)
    self.farmId  = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotDeliveryOrderEvent:run(connection)
    if not g_server or not g_DepotManager then return end
    local ds = g_DepotManager.deliverySystem
    if not ds then return end

    local ok, errKey = ds:placeOrder(self.depotId, self.farmId)
    if ok then
        DepotDeliverySyncEvent.broadcast(self.depotId)
    else
        DepotLogger.warning("DeliveryOrder rejected: depot=%d farm=%d reason=%s",
            self.depotId, self.farmId, tostring(errKey))
    end
end

function DepotDeliveryOrderEvent.sendToServer(depotId, farmId)
    local evt = DepotDeliveryOrderEvent.new(depotId, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
