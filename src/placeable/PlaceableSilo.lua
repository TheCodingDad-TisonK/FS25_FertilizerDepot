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
    schema:setXMLSpecializationType()
end

function PlaceableSilo:onLoad(savegame)
    self[PlaceableSilo.SPEC_TABLE_NAME] = { siloId = nil }
end

function PlaceableSilo:onPostFinalizePlacement()
    if g_DepotManager then
        local spec = self[PlaceableSilo.SPEC_TABLE_NAME]
        spec.siloId = g_DepotManager:registerSilo(self)
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
