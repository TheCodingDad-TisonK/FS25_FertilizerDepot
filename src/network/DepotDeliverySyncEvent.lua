-- =========================================================
-- FS25 Fertilizer Depot - Delivery Sync Event (Server -> All Clients)
-- =========================================================
-- Sends current delivery state for one depot to all clients (or one joining client).
-- Clients apply the state to their local deliverySystem so the ORDER tab stays current.

---@class DepotDeliverySyncEvent
DepotDeliverySyncEvent = {}
DepotDeliverySyncEvent_mt = Class(DepotDeliverySyncEvent, Event)

InitEventClass(DepotDeliverySyncEvent, "DepotDeliverySyncEvent")

function DepotDeliverySyncEvent.emptyNew()
    return Event.new(DepotDeliverySyncEvent_mt)
end

-- rec = delivery record or nil (nil clears the delivery for that depot on clients)
function DepotDeliverySyncEvent.new(depotId, rec)
    local self = DepotDeliverySyncEvent.emptyNew()
    self.depotId    = depotId
    self.hasRec     = (rec ~= nil)
    self.status      = rec and rec.status       or 0
    self.farmId      = rec and rec.farmId       or 1
    self.baseCost    = rec and rec.baseCost     or 0
    self.deliveryCost= rec and rec.deliveryCost or 0
    self.items       = rec and rec.items        or {}
    return self
end

function DepotDeliverySyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,   self.depotId)
    streamWriteBool(streamId,    self.hasRec)
    if not self.hasRec then return end
    streamWriteUInt8(streamId,   self.status)
    streamWriteUInt8(streamId,   self.farmId)
    streamWriteFloat32(streamId, self.baseCost)
    streamWriteFloat32(streamId, self.deliveryCost)
    streamWriteUInt8(streamId,   math.min(#self.items, 255))
    for i = 1, math.min(#self.items, 255) do
        local item = self.items[i]
        streamWriteString(streamId,  item.fillTypeName or "")
        streamWriteFloat32(streamId, item.needed       or 0)
        streamWriteFloat32(streamId, item.baseCost     or 0)
    end
end

function DepotDeliverySyncEvent:readStream(streamId, connection)
    self.depotId     = streamReadInt32(streamId)
    self.hasRec      = streamReadBool(streamId)
    self.items       = {}
    if self.hasRec then
        self.status       = streamReadUInt8(streamId)
        self.farmId       = streamReadUInt8(streamId)
        self.baseCost     = streamReadFloat32(streamId)
        self.deliveryCost = streamReadFloat32(streamId)
        local count = streamReadUInt8(streamId)
        for _ = 1, count do
            local name   = streamReadString(streamId)
            local liters = streamReadFloat32(streamId)
            local cost   = streamReadFloat32(streamId)
            local ftIdx  = 0
            if g_fillTypeManager then
                ftIdx = g_fillTypeManager:getFillTypeIndexByName(name) or 0
            end
            table.insert(self.items, {
                fillTypeName  = name,
                fillTypeIndex = ftIdx,
                displayName   = name,
                needed        = liters,
                baseCost      = cost,
            })
        end
    end
    self:run(connection)
end

function DepotDeliverySyncEvent:run(connection)
    if g_server then return end   -- server is the source of truth
    if not g_DepotManager then return end
    local ds = g_DepotManager.deliverySystem
    if not ds then return end

    if not self.hasRec then
        ds.deliveries[self.depotId] = nil
    else
        ds.deliveries[self.depotId] = {
            status       = self.status,
            depotId      = self.depotId,
            farmId       = self.farmId,
            baseCost     = self.baseCost,
            deliveryCost = self.deliveryCost,
            items        = self.items,
            vehicle      = nil,
        }
    end

    -- Refresh the ORDER tab if it is currently visible
    local dlg = g_DepotManager.activeDialog
    if dlg and dlg.tab == "order" then
        dlg:refresh()
    end
end

-- Broadcast current delivery state for depotId to all clients.
function DepotDeliverySyncEvent.broadcast(depotId)
    if not g_server or not g_DepotManager then return end
    local rec = g_DepotManager.deliverySystem
                and g_DepotManager.deliverySystem:getDelivery(depotId)
    g_server:broadcastEvent(DepotDeliverySyncEvent.new(depotId, rec))
end

-- Send current delivery state to a single joining client.
function DepotDeliverySyncEvent.sendToClient(connection, depotId)
    if not g_server or not g_DepotManager then return end
    local rec = g_DepotManager.deliverySystem
                and g_DepotManager.deliverySystem:getDelivery(depotId)
    connection:sendEvent(DepotDeliverySyncEvent.new(depotId, rec))
end
