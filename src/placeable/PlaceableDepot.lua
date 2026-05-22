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
end

-- ─── Save ────────────────────────────────────────────────

function PlaceableDepot:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec or not spec.depotId then return end
    if not g_DepotManager then return end
    g_DepotManager.depotSystem:saveToXML(xmlFile, spec.depotId, key .. ".storage")
end
