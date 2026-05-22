-- =========================================================
-- FS25 Fertilizer Depot - Delivery Complete Event (Client -> Server)
-- =========================================================

---@class DepotDeliveryCompleteEvent
DepotDeliveryCompleteEvent = {}
DepotDeliveryCompleteEvent_mt = Class(DepotDeliveryCompleteEvent, Event)

InitEventClass(DepotDeliveryCompleteEvent, "DepotDeliveryCompleteEvent")

function DepotDeliveryCompleteEvent.emptyNew()
    return Event.new(DepotDeliveryCompleteEvent_mt)
end

function DepotDeliveryCompleteEvent.new(depotId, farmId)
    local self = DepotDeliveryCompleteEvent.emptyNew()
    self.depotId = depotId
    self.farmId  = farmId
    return self
end

function DepotDeliveryCompleteEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.depotId or 0)
    streamWriteUInt8(streamId,  self.farmId  or 1)
end

function DepotDeliveryCompleteEvent:readStream(streamId, connection)
    self.depotId = streamReadInt32(streamId)
    self.farmId  = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotDeliveryCompleteEvent:run(connection)
    if not g_server or not g_DepotManager then return end
    local ds = g_DepotManager.deliverySystem
    if not ds then return end

    local ok, typeCount = ds:completeDelivery(self.depotId, self.farmId)
    if ok then
        -- Sync delivery state (cleared) then storage (restocked)
        DepotDeliverySyncEvent.broadcast(self.depotId)
        g_DepotManager:broadcastSync(self.depotId)
        DepotLogger.info("Delivery complete broadcast sent: depot=%d types=%d",
            self.depotId, typeCount or 0)
    else
        DepotLogger.warning("DeliveryComplete rejected: depot=%d farm=%d reason=%s",
            self.depotId, self.farmId, tostring(typeCount))
    end
end

function DepotDeliveryCompleteEvent.sendToServer(depotId, farmId)
    local evt = DepotDeliveryCompleteEvent.new(depotId, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
