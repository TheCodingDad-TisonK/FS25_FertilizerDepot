-- =========================================================
-- FS25 Fertilizer Depot - Product Order Event (Client -> Server)
-- Orders a physical bigBag or liquidTank spawned at the depot.
-- =========================================================

---@class DepotProductOrderEvent
DepotProductOrderEvent = {}
DepotProductOrderEvent_mt = Class(DepotProductOrderEvent, Event)

InitEventClass(DepotProductOrderEvent, "DepotProductOrderEvent")

function DepotProductOrderEvent.emptyNew()
    local self = Event.new(DepotProductOrderEvent_mt)
    return self
end

function DepotProductOrderEvent.new(depotId, fillTypeName, fillTypeIndex, quantity, farmId)
    local self = DepotProductOrderEvent.emptyNew()
    self.depotId       = depotId
    self.fillTypeName  = fillTypeName
    self.fillTypeIndex = fillTypeIndex
    self.quantity      = quantity
    self.farmId        = farmId
    return self
end

function DepotProductOrderEvent:readStream(streamId, connection)
    self.depotId       = streamReadInt32(streamId)
    self.fillTypeName  = streamReadString(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self.quantity      = streamReadUInt8(streamId)
    self.farmId        = streamReadUInt8(streamId)
    self:run(connection)
end

function DepotProductOrderEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,  self.depotId       or 0)
    streamWriteString(streamId, self.fillTypeName  or "")
    streamWriteInt32(streamId,  self.fillTypeIndex  or 0)
    streamWriteUInt8(streamId,  self.quantity       or 1)
    streamWriteUInt8(streamId,  self.farmId         or 1)
end

function DepotProductOrderEvent:run(connection)
    if not g_server or not g_DepotManager then return end

    local placeable = g_DepotManager.depots[self.depotId]
    local spawnX, spawnZ = 0, 0

    -- Use unload node position as spawn point (vehicles park there anyway)
    local unloadNode = g_DepotManager.depotUnloadNodes[self.depotId]
    if unloadNode then
        local wx, wy, wz = getWorldTranslation(unloadNode)
        spawnX, spawnZ = wx, wz
    elseif placeable and placeable.rootNode then
        local wx, wy, wz = getWorldTranslation(placeable.rootNode)
        spawnX, spawnZ = wx, wz
    end

    local ok, msgKey = g_DepotManager.depotSystem:orderProduct(
        self.depotId, self.fillTypeName, self.fillTypeIndex,
        self.quantity, spawnX, spawnZ, self.farmId)

    if ok then
        g_DepotManager:broadcastSync(self.depotId)
    end

    DepotLogger.info("ProductOrder result: %s (%s) qty=%d farm=%d msg=%s",
        self.fillTypeName, ok and "OK" or "FAIL", self.quantity, self.farmId, tostring(msgKey))
end

function DepotProductOrderEvent.sendToServer(depotId, fillTypeName, fillTypeIndex, quantity, farmId)
    local evt = DepotProductOrderEvent.new(depotId, fillTypeName, fillTypeIndex, quantity, farmId)
    if g_server then
        evt:run(nil)
    else
        g_client:getServerConnection():sendEvent(evt)
    end
end
