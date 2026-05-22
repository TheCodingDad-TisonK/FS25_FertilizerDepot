-- =========================================================
-- FS25 Fertilizer Depot - Pickup Zone Placeable
-- =========================================================
-- Player places this building near the in-game shop / dealer
-- to designate the supplier pickup point for delivery orders.
-- Registers with DepotManager so the proximity system can
-- detect the player and show the E-key collect prompt.

local modName = g_currentModName

---@class PlaceableDepotPickup
PlaceableDepotPickup = {}
PlaceableDepotPickup.SPEC_TABLE_NAME = "spec_" .. modName .. ".fertilizerDepotPickup"

function PlaceableDepotPickup.prerequisitesPresent(...)
    return true
end

function PlaceableDepotPickup.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",                 PlaceableDepotPickup)
    SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement", PlaceableDepotPickup)
    SpecializationUtil.registerEventListener(placeableType, "onDelete",               PlaceableDepotPickup)
end

function PlaceableDepotPickup.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("FertilizerDepotPickup")
    schema:register(XMLValueType.NODE_INDEX,
        basePath .. ".fertilizerDepotPickup#playerTrigger",
        "World position anchor for player proximity detection (defaults to rootNode)")
    schema:setXMLSpecializationType()
end

function PlaceableDepotPickup:onLoad(savegame)
    local spec = { pickupId = nil, playerTriggerNode = nil }
    self[PlaceableDepotPickup.SPEC_TABLE_NAME] = spec

    spec.playerTriggerNode = self.xmlFile:getValue(
        "placeable.fertilizerDepotPickup#playerTrigger", nil,
        self.components, self.i3dMappings)

    if spec.playerTriggerNode == nil then
        spec.playerTriggerNode = self.rootNode
        DepotLogger.info("PlaceableDepotPickup: no playerTrigger defined — using rootNode")
    end
end

function PlaceableDepotPickup:onPostFinalizePlacement()
    if g_DepotManager then
        local spec = self[PlaceableDepotPickup.SPEC_TABLE_NAME]
        spec.pickupId = g_DepotManager:registerPickup(self)
    end
end

function PlaceableDepotPickup:onDelete()
    local spec = self[PlaceableDepotPickup.SPEC_TABLE_NAME]
    if not spec then return end
    if g_DepotManager and spec.pickupId then
        g_DepotManager:unregisterPickup(spec.pickupId)
    end
    self[PlaceableDepotPickup.SPEC_TABLE_NAME] = nil
end
