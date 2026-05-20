-- =========================================================
-- FS25 Fertilizer Depot - Runtime Settings
-- =========================================================
-- Holds all admin-configurable values. Loaded from savegame
-- XML on mission start; synced to clients via DepotSettingsEvent.

---@class DepotSettings
DepotSettings = {}
local DepotSettings_mt = Class(DepotSettings)

-- Preset option tables (shown in the settings dialog)
DepotSettings.CAPACITY_OPTIONS   = {10000, 25000, 50000, 100000, 250000}
DepotSettings.SELL_RATIO_OPTIONS = {0.50, 0.60, 0.70, 0.80, 0.90}
DepotSettings.BUY_MULT_OPTIONS   = {0.75, 1.00, 1.25, 1.50}

DepotSettings.DEFAULTS = {
    seasonalPricing = true,
    storageCapacity = 50000,
    sellRatio       = 0.80,
    buyMultiplier   = 1.00,
}

function DepotSettings.new()
    local self = setmetatable({}, DepotSettings_mt)
    self:reset()
    return self
end

function DepotSettings:reset()
    for k, v in pairs(DepotSettings.DEFAULTS) do
        self[k] = v
    end
end

-- ─── Helpers ─────────────────────────────────────────────

-- Returns index (1-based) into options table, or 1 if not found.
local function findIndex(tbl, value)
    for i, v in ipairs(tbl) do
        if math.abs(v - value) < 0.001 then return i end
    end
    return 1
end

function DepotSettings:getCapacityIndex()
    return findIndex(DepotSettings.CAPACITY_OPTIONS, self.storageCapacity)
end

function DepotSettings:getSellRatioIndex()
    return findIndex(DepotSettings.SELL_RATIO_OPTIONS, self.sellRatio)
end

function DepotSettings:getBuyMultiplierIndex()
    return findIndex(DepotSettings.BUY_MULT_OPTIONS, self.buyMultiplier)
end

-- ─── Save / Load ─────────────────────────────────────────

function DepotSettings:saveToXML(xmlFile, key)
    xmlFile:setBool(key .. "#seasonalPricing", self.seasonalPricing)
    xmlFile:setFloat(key .. "#storageCapacity", self.storageCapacity)
    xmlFile:setFloat(key .. "#sellRatio",       self.sellRatio)
    xmlFile:setFloat(key .. "#buyMultiplier",   self.buyMultiplier)
end

function DepotSettings:loadFromXML(xmlFile, key)
    self.seasonalPricing = xmlFile:getBool(key .. "#seasonalPricing",
        DepotSettings.DEFAULTS.seasonalPricing)
    self.storageCapacity = xmlFile:getFloat(key .. "#storageCapacity",
        DepotSettings.DEFAULTS.storageCapacity)
    self.sellRatio = xmlFile:getFloat(key .. "#sellRatio",
        DepotSettings.DEFAULTS.sellRatio)
    self.buyMultiplier = xmlFile:getFloat(key .. "#buyMultiplier",
        DepotSettings.DEFAULTS.buyMultiplier)
end

-- ─── Write / Read stream (for client sync) ───────────────

function DepotSettings:writeStream(streamId)
    streamWriteBool(streamId, self.seasonalPricing)
    streamWriteFloat32(streamId, self.storageCapacity)
    streamWriteFloat32(streamId, self.sellRatio)
    streamWriteFloat32(streamId, self.buyMultiplier)
end

function DepotSettings:readStream(streamId)
    self.seasonalPricing = streamReadBool(streamId)
    self.storageCapacity = streamReadFloat32(streamId)
    self.sellRatio       = streamReadFloat32(streamId)
    self.buyMultiplier   = streamReadFloat32(streamId)
end
