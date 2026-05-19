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
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#vehicleTrigger",
        "Vehicle proximity trigger node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#playerTrigger",
        "Player interaction trigger node")
    schema:register(XMLValueType.STRING, basePath .. ".storage.fill(?)#type",   "Fill type name")
    schema:register(XMLValueType.FLOAT,  basePath .. ".storage.fill(?)#liters", "Stored liters")
    schema:setXMLSpecializationType()
end

-- ─── onLoad — runs on ALL machines ───────────────────────

function PlaceableDepot:onLoad(savegame)
    local spec = {}
    self[PlaceableDepot.SPEC_TABLE_NAME] = spec

    spec.depotId = nil
    spec.savegame = savegame

    -- Load trigger nodes here so both server and clients have them
    spec.vehicleTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#vehicleTrigger", nil,
        self.components, self.i3dMappings)

    spec.playerTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#playerTrigger", nil,
        self.components, self.i3dMappings)

    if spec.vehicleTriggerNode == nil then
        DepotLogger.warning("vehicleTrigger node not found — check i3dMappings")
    end
    if spec.playerTriggerNode == nil then
        DepotLogger.warning("playerTrigger node not found — check i3dMappings")
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

    -- Vehicle trigger: server only (drives authoritative buy/sell logic)
    if g_server and spec.vehicleTriggerNode then
        addTrigger(spec.vehicleTriggerNode, "onVehicleTrigger", self)
    end

    -- Player trigger: ALL machines so dialog opens for any local player
    if spec.playerTriggerNode then
        addTrigger(spec.playerTriggerNode, "onPlayerTrigger", self)
    end
end

-- ─── Trigger Callbacks ───────────────────────────────────

function PlaceableDepot:onVehicleTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    -- Server only (vehicle trigger only registered on server)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec or not spec.depotId then return end

    local vehicle = g_currentMission:getNodeObject(otherId)
    if not vehicle or not vehicle.getFillUnits then return end

    if onEnter then
        g_DepotManager.depotSystem:addVehicleNearby(spec.depotId, vehicle)
        DepotLogger.debug("Vehicle entered depot #%d: %s", spec.depotId,
            tostring(vehicle.configFileName))
    elseif onLeave then
        g_DepotManager.depotSystem:removeVehicleNearby(spec.depotId, vehicle)
    end
end

function PlaceableDepot:onPlayerTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    -- Fires locally on each machine. Only respond to the local player.
    if not g_localPlayer then return end
    if otherId ~= g_localPlayer.rootNode then return end

    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec then return end

    -- depotId may be nil on client — use the stored network id instead
    local depotId = spec.depotId or spec.netDepotId
    if not depotId then return end

    if onEnter then
        if g_DepotManager then
            g_DepotManager:openDialog(depotId)
        end
    elseif onLeave then
        if g_DepotManager then
            g_DepotManager:closeDialog()
        end
    end
end

-- ─── onDelete ────────────────────────────────────────────

function PlaceableDepot:onDelete()
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec then return end

    -- Vehicle trigger: only server registered it
    if g_server and spec.vehicleTriggerNode then
        removeTrigger(spec.vehicleTriggerNode)
    end

    -- Player trigger: all machines registered it
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
    -- Server → joining client: send depotId and initial storage state
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
    -- Client receives depotId and initial storage state from server
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]

    local netId = streamReadInt32(streamId)
    spec.netDepotId = netId  -- used by onPlayerTrigger on clients

    -- Ensure a local depot state table exists for display purposes
    if g_DepotManager then
        if not g_DepotManager.depotSystem:getDepot(netId) then
            g_DepotManager.depotSystem._depots[netId] = {
                id             = netId,
                storageLevel   = {},
                vehiclesNearby = {},
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
