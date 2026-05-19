-- =========================================================
-- FS25 Fertilizer Depot - SoilFertilizer Integration Bridge
-- =========================================================
-- Reads fill type list and base prices from FS25_SoilFertilizer.
-- Falls back to vanilla fill types if SF is not installed.
-- =========================================================

---@class SoilFertilizerBridge
SoilFertilizerBridge = {}
local SoilFertilizerBridge_mt = Class(SoilFertilizerBridge)

function SoilFertilizerBridge.new()
    local self = setmetatable({}, SoilFertilizerBridge_mt)
    self._fillTypeList = nil  -- cached on first call
    return self
end

-- Returns true when FS25_SoilFertilizer is present and initialized
function SoilFertilizerBridge:isInstalled()
    return g_SoilFertilityManager ~= nil
end

-- Returns ordered list of {name, fillTypeIndex, pricePerLiter, displayName} tables.
-- Includes ALL SF custom types when SF is installed, vanilla fallback otherwise.
-- Result is cached after first call (fill types don't change at runtime).
function SoilFertilizerBridge:getFillTypeList()
    if self._fillTypeList then
        return self._fillTypeList
    end

    local list = {}

    if self:isInstalled() then
        -- Build from SF's registered fill type names
        for _, name in ipairs(DepotConstants.SF_FILL_TYPE_NAMES) do
            local ftIndex = g_fillTypeManager and
                g_fillTypeManager:getFillTypeIndexByName(name)
            if ftIndex and ftIndex > 0 then
                local ft = g_fillTypeManager:getFillTypeByIndex(ftIndex)
                local price = (ft and ft.economy and ft.economy.pricePerLiter) or 1.00
                local title = (ft and ft.title) or name
                table.insert(list, {
                    name          = name,
                    fillTypeIndex = ftIndex,
                    pricePerLiter = price,
                    displayName   = title,
                })
            end
        end
    end

    -- Always include vanilla types not covered by SF list
    for _, entry in ipairs(DepotConstants.VANILLA_FILL_TYPES) do
        local alreadyIn = false
        for _, existing in ipairs(list) do
            if existing.name == entry.name then alreadyIn = true; break end
        end
        if not alreadyIn then
            local ftIndex = g_fillTypeManager and
                g_fillTypeManager:getFillTypeIndexByName(entry.name)
            if ftIndex and ftIndex > 0 then
                local ft = g_fillTypeManager:getFillTypeByIndex(ftIndex)
                local price = (ft and ft.economy and ft.economy.pricePerLiter)
                    or entry.pricePerLiter
                local title = (ft and ft.title) or entry.name
                table.insert(list, {
                    name          = entry.name,
                    fillTypeIndex = ftIndex,
                    pricePerLiter = price,
                    displayName   = title,
                })
            end
        end
    end

    self._fillTypeList = list
    return list
end

-- Returns the base price per liter for a fill type by name.
-- Uses game's registered price; falls back to DepotConstants.VANILLA_FILL_TYPES table.
function SoilFertilizerBridge:getBasePrice(fillTypeName)
    local ftIndex = g_fillTypeManager and
        g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    if ftIndex and ftIndex > 0 then
        local ft = g_fillTypeManager:getFillTypeByIndex(ftIndex)
        if ft and ft.economy and ft.economy.pricePerLiter then
            return ft.economy.pricePerLiter
        end
    end
    for _, entry in ipairs(DepotConstants.VANILLA_FILL_TYPES) do
        if entry.name == fillTypeName then
            return entry.pricePerLiter
        end
    end
    return 1.00  -- safe fallback
end

-- Returns display name for a fill type index
function SoilFertilizerBridge:getDisplayName(fillTypeIndex)
    if not g_fillTypeManager then return tostring(fillTypeIndex) end
    local ft = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    return (ft and ft.title) or tostring(fillTypeIndex)
end

-- Invalidate cache (call if fill types change at runtime)
function SoilFertilizerBridge:invalidateCache()
    self._fillTypeList = nil
end
