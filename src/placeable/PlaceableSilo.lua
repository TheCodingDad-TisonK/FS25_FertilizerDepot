-- =========================================================
-- FS25 Fertilizer Depot - Silo Placeable Specialization
-- =========================================================
-- Registers placed silos with DepotManager so the proximity
-- system can detect vehicles near the silo and trigger the
-- pre-order fill flow.

local modName = g_currentModName

---@class PlaceableSilo
PlaceableSilo = {}
PlaceableSilo.SPEC_TABLE_NAME = "spec_" .. modName .. ".fertilizerSilo"

function PlaceableSilo.prerequisitesPresent(...)
    return true
end

function PlaceableSilo.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",                 PlaceableSilo)
    SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement", PlaceableSilo)
    SpecializationUtil.registerEventListener(placeableType, "onDelete",               PlaceableSilo)
end

function PlaceableSilo.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("FertilizerSilo")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".fertilizerSilo#loadingStation",
        "Loading station node used as vehicle search origin for fill orders")
    schema:setXMLSpecializationType()
end

function PlaceableSilo:onLoad(savegame)
    local spec = { siloId = nil, loadStationNode = nil }
    self[PlaceableSilo.SPEC_TABLE_NAME] = spec
    spec.loadStationNode = self.xmlFile:getValue(
        "placeable.fertilizerSilo#loadingStation", nil,
        self.components, self.i3dMappings)
    if spec.loadStationNode == nil then
        DepotLogger.warning("PlaceableSilo: loadingStation node not found — using rootNode for vehicle search")
    end
end

function PlaceableSilo:onPostFinalizePlacement()
    if g_DepotManager then
        local spec = self[PlaceableSilo.SPEC_TABLE_NAME]
        spec.siloId = g_DepotManager:registerSilo(self, spec.loadStationNode)
    end
end

function PlaceableSilo:onDelete()
    local spec = self[PlaceableSilo.SPEC_TABLE_NAME]
    if not spec then return end
    if g_DepotManager and spec.siloId then
        g_DepotManager:unregisterSilo(spec.siloId)
    end
    self[PlaceableSilo.SPEC_TABLE_NAME] = nil
end
