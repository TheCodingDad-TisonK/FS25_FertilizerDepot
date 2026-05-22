-- =========================================================
-- FS25 Fertilizer Depot - Delivery Pickup Event (Client -> Server)
-- =========================================================

---@class DepotDeliveryPickupEvent
DepotDeliveryPickupEvent = {}
DepotDeliveryPickupEvent_mt = Class(DepotDeliveryPickupEvent, Event)

InitEventClass(DepotDeliveryPickupEvent, "DepotDeliveryPickupEvent")

function DepotDeliveryPickupEvent.emptyNew()
    return Event.new(DepotDeliveryPickupEvent_mt)
end

function DepotDeliveryPickupEvent.new(depotId, farmId)
    local self = DepotDeliveryPickupEvent.emptyNew()
    self.depotId = depotId
    self.farmId  = farmId
    return self
end

function DepotDeliveryPickupEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.depotId or 0)
    streamWriteUInt8(streamId,  self.farmId  or 1)
end

function DepotDeliveryPickupEvent:readStream(streamId, connection)
    self.depotId = streamReadInt32(streamId)
    self.farmId  = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotDeliveryPickupEvent:run(connection)
    if not g_server or not g_DepotManager then return end
    local ds = g_DepotManager.deliverySystem
    if not ds then return end

    local ok, errKey = ds:confirmPickup(self.depotId, self.farmId)
    if ok then
        DepotDeliverySyncEvent.broadcast(self.depotId)
    else
        DepotLogger.warning("DeliveryPickup rejected: depot=%d farm=%d reason=%s",
            self.depotId, self.farmId, tostring(errKey))
    end
end

function DepotDeliveryPickupEvent.sendToServer(depotId, farmId)
    local evt = DepotDeliveryPickupEvent.new(depotId, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
