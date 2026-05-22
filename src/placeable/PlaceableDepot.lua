-- =========================================================
-- FS25 Fertilizer Depot - Placeable Specialization
-- =========================================================

local modName = g_currentModName

---@class PlaceableDepot
PlaceableDepot = {}
PlaceableDepot.SPEC_TABLE_NAME = "spec_" .. modName .. ".fertilizerDepot"

function PlaceableDepot.prerequisitesPresent(...)
    return true
end

function PlaceableDepot.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",                  PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement",  PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onDelete",                PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream",             PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream",            PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "saveToXMLFile",            PlaceableDepot)
end

function PlaceableDepot.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("FertilizerDepot")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#playerTrigger",
        "Player walk-in trigger node (inside building)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#unloadTrigger",
        "Vehicle unload marker node (front of selling area)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#productSpawnMarker",
        "Product output node — bags and tanks spawn here")
    schema:register(XMLValueType.STRING, basePath .. ".storage.fill(?)#type",   "Fill type name")
    schema:register(XMLValueType.FLOAT,  basePath .. ".storage.fill(?)#liters", "Stored liters")
    schema:register(XMLValueType.INT,    basePath .. ".delivery#status",         "Delivery status (0=none 1=pending 2=loaded)")
    schema:register(XMLValueType.INT,    basePath .. ".delivery#farmId",         "Delivery farm ID")
    schema:register(XMLValueType.FLOAT,  basePath .. ".delivery#baseCost",       "Delivery base cost")
    schema:register(XMLValueType.FLOAT,  basePath .. ".delivery#deliveryCost",   "Delivery total cost with fee")
    schema:register(XMLValueType.STRING, basePath .. ".delivery.item(?)#name",   "Fill type name for delivery item")
    schema:register(XMLValueType.FLOAT,  basePath .. ".delivery.item(?)#liters", "Liters for delivery item")
    schema:register(XMLValueType.FLOAT,  basePath .. ".delivery.item(?)#cost",   "Base cost for delivery item")
    schema:setXMLSpecializationType()
end

-- ─── onLoad ──────────────────────────────────────────────

function PlaceableDepot:onLoad(savegame)
    local spec = {}
    self[PlaceableDepot.SPEC_TABLE_NAME] = spec
    spec.depotId         = nil
    spec.savegame        = savegame

    spec.playerTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#playerTrigger", nil,
        self.components, self.i3dMappings)

    spec.unloadTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#unloadTrigger", nil,
        self.components, self.i3dMappings)

    spec.productSpawnNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#productSpawnMarker", nil,
        self.components, self.i3dMappings)

    if spec.playerTriggerNode == nil then
        DepotLogger.warning("playerTrigger node not found — check i3dMappings")
    else
        DepotLogger.debug("playerTrigger node loaded: %s", tostring(spec.playerTriggerNode))
    end
end

-- ─── onPostFinalizePlacement ──────────────────────────────

function PlaceableDepot:onPostFinalizePlacement()
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]

    if g_server and g_DepotManager then
        spec.depotId = g_DepotManager:registerDepot(self)
        if spec.unloadTriggerNode then
            g_DepotManager:registerDepotUnloadNode(spec.depotId, spec.unloadTriggerNode)
        end
        if spec.productSpawnNode then
            g_DepotManager:registerDepotProductSpawnNode(spec.depotId, spec.productSpawnNode)
        end
    end

    if g_server and spec.depotId and spec.savegame then
        local sg = spec.savegame
        g_DepotManager.depotSystem:loadFromXML(
            sg.xmlFile, spec.depotId, sg.key .. ".storage")
        if g_DepotManager.deliverySystem then
            g_DepotManager.deliverySystem:loadDeliveryFromXML(
                sg.xmlFile, spec.depotId, sg.key .. ".delivery")
        end
    end
    spec.savegame = nil
end

-- ─── onDelete ────────────────────────────────────────────

function PlaceableDepot:onDelete()
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec then return end

    if g_DepotManager and spec.depotId then
        g_DepotManager:unregisterDepot(spec.depotId)
    end

    self[PlaceableDepot.SPEC_TABLE_NAME] = nil
end

-- ─── Network Sync ────────────────────────────────────────

function PlaceableDepot:onWriteStream(streamId, connection)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    streamWriteInt32(streamId, spec.depotId or 0)

    local depot = g_DepotManager and g_DepotManager.depotSystem:getDepot(spec.depotId)
    if depot then
        local count = 0
        for _ in pairs(depot.storageLevel) do count = count + 1 end
        streamWriteUInt16(streamId, count)
        for name, liters in pairs(depot.storageLevel) do
            streamWriteString(streamId, name)
            streamWriteFloat32(streamId, liters)
        end
    else
        streamWriteUInt16(streamId, 0)
    end

    -- Delivery state for joining client
    local rec = g_DepotManager and g_DepotManager.deliverySystem
                and g_DepotManager.deliverySystem:getDelivery(spec.depotId)
    streamWriteBool(streamId, rec ~= nil)
    if rec then
        streamWriteUInt8(streamId,   rec.status)
        streamWriteUInt8(streamId,   rec.farmId)
        streamWriteFloat32(streamId, rec.baseCost)
        streamWriteFloat32(streamId, rec.deliveryCost)
        streamWriteUInt8(streamId,   math.min(#rec.items, 255))
        for i = 1, math.min(#rec.items, 255) do
            local item = rec.items[i]
            streamWriteString(streamId,  item.fillTypeName or "")
            streamWriteFloat32(streamId, item.needed       or 0)
            streamWriteFloat32(streamId, item.baseCost     or 0)
        end
    end
end

function PlaceableDepot:onReadStream(streamId, connection)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]

    local netId = streamReadInt32(streamId)
    spec.netDepotId = netId

    if g_DepotManager then
        if not g_DepotManager.depotSystem:getDepot(netId) then
            g_DepotManager.depotSystem._depots[netId] = {
                id           = netId,
                storageLevel = {},
            }
        end
        g_DepotManager.depots[netId] = self
        spec.netDepotId = netId
        g_DepotManager.depotNodes[netId] = spec.playerTriggerNode or self.rootNode
        if spec.unloadTriggerNode then
            g_DepotManager:registerDepotUnloadNode(netId, spec.unloadTriggerNode)
        end
        if spec.productSpawnNode then
            g_DepotManager:registerDepotProductSpawnNode(netId, spec.productSpawnNode)
        end
    end

    local count = streamReadUInt16(streamId)
    local depot = g_DepotManager and g_DepotManager.depotSystem:getDepot(netId)
    for _ = 1, count do
        local name   = streamReadString(streamId)
        local liters = streamReadFloat32(streamId)
        if depot then
            depot.storageLevel[name] = liters
        end
    end

    -- Read delivery state
    local hasRec = streamReadBool(streamId)
    if hasRec and g_DepotManager and g_DepotManager.deliverySystem then
        local status       = streamReadUInt8(streamId)
        local farmId       = streamReadUInt8(streamId)
        local baseCost     = streamReadFloat32(streamId)
        local deliveryCost = streamReadFloat32(streamId)
        local itemCount    = streamReadUInt8(streamId)
        local items        = {}
        for _ = 1, itemCount do
            local name   = streamReadString(streamId)
            local liters = streamReadFloat32(streamId)
            local cost   = streamReadFloat32(streamId)
            local ftIdx  = g_fillTypeManager
                           and g_fillTypeManager:getFillTypeIndexByName(name) or 0
            table.insert(items, {
                fillTypeName  = name,
                fillTypeIndex = ftIdx,
                displayName   = name,
                needed        = liters,
                baseCost      = cost,
            })
        end
        g_DepotManager.deliverySystem.deliveries[netId] = {
            status       = status,
            depotId      = netId,
            farmId       = farmId,
            baseCost     = baseCost,
            deliveryCost = deliveryCost,
            items        = items,
            vehicle      = nil,
        }
    elseif g_DepotManager and g_DepotManager.deliverySystem then
        g_DepotManager.deliverySystem.deliveries[netId] = nil
    end
end

-- ─── Save ────────────────────────────────────────────────

function PlaceableDepot:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec or not spec.depotId then return end
    if not g_DepotManager then return end
    g_DepotManager.depotSystem:saveToXML(xmlFile, spec.depotId, key .. ".storage")
    if g_DepotManager.deliverySystem then
        g_DepotManager.deliverySystem:saveDeliveryToXML(xmlFile, key .. ".delivery", spec.depotId)
    end
end
