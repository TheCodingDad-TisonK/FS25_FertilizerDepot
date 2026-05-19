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
    SpecializationUtil.registerEventListener(placeableType, "onLoad",               PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement", PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onDelete",             PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream",          PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream",         PlaceableDepot)
    SpecializationUtil.registerEventListener(placeableType, "saveToXMLFile",         PlaceableDepot)
end

function PlaceableDepot.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("FertilizerDepot")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#vehicleTrigger",
        "Vehicle proximity trigger node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerDepot#playerTrigger",
        "Player interaction trigger node")
    schema:register(XMLValueType.STRING,  basePath .. ".storage.fill(?)#type",   "Fill type name")
    schema:register(XMLValueType.FLOAT,   basePath .. ".storage.fill(?)#liters", "Stored liters")
    schema:setXMLSpecializationType()
end

-- ─── onLoad ──────────────────────────────────────────────

function PlaceableDepot:onLoad(savegame)
    local spec = {}
    self[PlaceableDepot.SPEC_TABLE_NAME] = spec

    spec.depotId          = nil
    spec.vehicleTriggerNode = nil
    spec.playerTriggerNode  = nil
    spec.savegame         = savegame
end

-- ─── onPostFinalizePlacement ──────────────────────────────

function PlaceableDepot:onPostFinalizePlacement()
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]

    -- Read trigger nodes from i3dMappings via XML
    spec.vehicleTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#vehicleTrigger", nil,
        self.components, self.i3dMappings)

    spec.playerTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepot#playerTrigger", nil,
        self.components, self.i3dMappings)

    -- Register with DepotManager (server and client)
    if g_DepotManager then
        spec.depotId = g_DepotManager:registerDepot(self)
    end

    -- Load saved storage state (server only on savegame resume)
    if g_server and spec.depotId and spec.savegame then
        g_DepotManager.depotSystem:loadFromXML(
            self.xmlFile, spec.depotId, "placeable.storage")
    end

    -- Install triggers (server only — triggers drive authoritative logic)
    if g_server then
        if spec.vehicleTriggerNode then
            addTrigger(spec.vehicleTriggerNode,
                "onVehicleTrigger", self)
        end
        if spec.playerTriggerNode then
            addTrigger(spec.playerTriggerNode,
                "onPlayerTrigger", self)
        end
    end

    spec.savegame = nil  -- release reference after load
end

-- ─── Trigger Callbacks ───────────────────────────────────

function PlaceableDepot:onVehicleTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    if not g_server then return end
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec.depotId then return end

    local vehicle = g_currentMission:getNodeObject(otherId)
    if not vehicle or not vehicle.getFillUnits then return end

    if onEnter then
        g_DepotManager.depotSystem:addVehicleNearby(spec.depotId, vehicle)
        DepotLogger.debug("Vehicle entered depot #%d trigger: %s",
            spec.depotId, tostring(vehicle.configFileName))
    elseif onLeave then
        g_DepotManager.depotSystem:removeVehicleNearby(spec.depotId, vehicle)
    end
end

function PlaceableDepot:onPlayerTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    -- Player trigger fires on all machines; only act for local player
    if not g_localPlayer then return end
    if otherId ~= g_localPlayer.rootNode then return end

    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec.depotId then return end

    if onEnter then
        if g_DepotManager then
            g_DepotManager:openDialog(spec.depotId)
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

    if g_server then
        if spec.vehicleTriggerNode then
            removeTrigger(spec.vehicleTriggerNode)
        end
        if spec.playerTriggerNode then
            removeTrigger(spec.playerTriggerNode)
        end
    end

    if g_DepotManager and spec.depotId then
        g_DepotManager:unregisterDepot(spec.depotId)
    end

    self[PlaceableDepot.SPEC_TABLE_NAME] = nil
end

-- ─── Network Sync ────────────────────────────────────────

function PlaceableDepot:onReadStream(streamId, connection)
    -- Client receives depot ID assigned by server
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    spec.depotId = streamReadInt32(streamId)
    if g_DepotManager then
        -- Ensure a local depot state table exists for this id
        if not g_DepotManager.depotSystem:getDepot(spec.depotId) then
            g_DepotManager.depotSystem._depots[spec.depotId] = {
                id            = spec.depotId,
                storageLevel  = {},
                vehiclesNearby = {},
            }
        end
        g_DepotManager.depots[spec.depotId] = self
    end
    -- Read initial storage state
    local count = streamReadUInt16(streamId)
    local depot = g_DepotManager and g_DepotManager.depotSystem:getDepot(spec.depotId)
    for _ = 1, count do
        local name   = streamReadString(streamId)
        local liters = streamReadFloat32(streamId)
        if depot then
            depot.storageLevel[name] = liters
        end
    end
end

function PlaceableDepot:onWriteStream(streamId, connection)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    streamWriteInt32(streamId, spec.depotId or 0)
    -- Send current storage state to joining client
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

-- ─── Save ────────────────────────────────────────────────

function PlaceableDepot:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[PlaceableDepot.SPEC_TABLE_NAME]
    if not spec or not spec.depotId then return end
    if not g_DepotManager then return end
    g_DepotManager.depotSystem:saveToXML(xmlFile, spec.depotId, key .. ".storage")
end
