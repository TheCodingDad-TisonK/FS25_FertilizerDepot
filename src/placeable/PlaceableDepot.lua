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

-- registerFunctions: makes onPlayerTrigger callable as self:onPlayerTrigger()
-- Required so addTrigger(node, "onPlayerTrigger", self) can resolve the callback.
function PlaceableDepot.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "onPlayerTrigger",
        PlaceableDepot.onPlayerTrigger)
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
    spec.actionEventId   = nil

    spec.playerTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#playerTrigger", nil,
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

    -- Register with DepotManager (server only — authoritative state)
    if g_server and g_DepotManager then
        spec.depotId = g_DepotManager:registerDepot(self)
    end

    -- Load saved storage state
    if g_server and spec.depotId and spec.savegame then
        local sg = spec.savegame
        g_DepotManager.depotSystem:loadFromXML(
            sg.xmlFile, spec.depotId, sg.key .. ".storage")
    end
    spec.savegame = nil

    -- Register player trigger on ALL machines so the local player gets the prompt.
    if spec.playerTriggerNode then
        addTrigger(spec.playerTriggerNode, "onPlayerTrigger", self)
        DepotLogger.debug("Player trigger registered on node %s", tostring(spec.playerTriggerNode))
    end
end

-- ─── Player Trigger ──────────────────────────────────────

-- Walk up the parent chain to check if otherId belongs to g_localPlayer.
-- Placeable specialization callbacks receive physics child nodes, not rootNode directly.
local function isLocalPlayer(otherId)
    if not g_localPlayer then return false end
    local target = g_localPlayer.rootNode
    if not target then return false end
    local node = otherId
    for _ = 1, 8 do
        if node == nil or node == 0 then break end
        if node == target then return true end
        node = getParent(node)
    end
    return false
end

function PlaceableDepot:onPlayerTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    if onStay then return end
    if not isLocalPlayer(otherId) then return end

    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec then return end

    local depotId = spec.depotId or spec.netDepotId
    if not depotId then
        DepotLogger.warning("onPlayerTrigger: depotId is nil")
        return
    end

    if onEnter then
        DepotLogger.debug("Player entered depot #%d", depotId)
        local function onActivate()
            if g_DepotManager then g_DepotManager:openDialog(depotId) end
        end
        local ok, evId = g_inputBinding:registerActionEvent(
            InputAction.ACTIVATE_HANDTOOL, self, onActivate, false, true, false, true)
        if ok then
            spec.actionEventId = evId
            g_inputBinding:setActionEventText(evId, g_i18n:getText("fd_depot_open_action"))
            g_inputBinding:setActionEventActive(evId, true)
        end
    elseif onLeave then
        DepotLogger.debug("Player left depot #%d", depotId)
        if spec.actionEventId then
            g_inputBinding:removeActionEvent(spec.actionEventId)
            spec.actionEventId = nil
        end
        if g_DepotManager then g_DepotManager:closeDialog() end
    end
end

-- ─── onDelete ────────────────────────────────────────────

function PlaceableDepot:onDelete()
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec then return end

    if spec.actionEventId then
        g_inputBinding:removeActionEvent(spec.actionEventId)
        spec.actionEventId = nil
    end

    if spec.playerTriggerNode then
        removeTrigger(spec.playerTriggerNode)
    end

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
