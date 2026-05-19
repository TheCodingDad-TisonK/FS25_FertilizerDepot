-- =========================================================
-- FS25 Fertilizer Depot - Pricing System
-- =========================================================

---@class DepotPricing
DepotPricing = {}
local DepotPricing_mt = Class(DepotPricing)

function DepotPricing.new(sfBridge)
    local self = setmetatable({}, DepotPricing_mt)
    self._sfBridge = sfBridge
    return self
end

-- Returns the current season multiplier based on game period (1-12).
function DepotPricing:getSeasonMultiplier()
    local env = g_currentMission and g_currentMission.environment
    local period = env and env.currentPeriod
    if period and DepotConstants.SEASON_MULTIPLIERS[period] then
        return DepotConstants.SEASON_MULTIPLIERS[period]
    end
    return DepotConstants.DEFAULT_SEASON_MULTIPLIER
end

-- Returns the season label key for the current period.
function DepotPricing:getSeasonKey()
    local env = g_currentMission and g_currentMission.environment
    local period = env and env.currentPeriod or 0
    if period >= 1 and period <= 3  then return "fd_season_spring" end
    if period >= 4 and period <= 6  then return "fd_season_summer" end
    if period >= 7 and period <= 9  then return "fd_season_fall"   end
    if period >= 10 and period <= 12 then return "fd_season_winter" end
    return "fd_season_summer"
end

-- Returns buy price per liter for fillTypeName (base × season multiplier).
function DepotPricing:getBuyPrice(fillTypeName)
    local base = self._sfBridge:getBasePrice(fillTypeName)
    return base * self:getSeasonMultiplier()
end

-- Returns sell price per liter (buy price × sell ratio).
function DepotPricing:getSellPrice(fillTypeName)
    return self:getBuyPrice(fillTypeName) * DepotConstants.SELL_RATIO
end

-- Returns total cost for purchasing a quantity at buy price.
function DepotPricing:calculateBuyCost(fillTypeName, liters)
    return self:getBuyPrice(fillTypeName) * liters
end

-- Returns total revenue for selling a quantity at sell price.
function DepotPricing:calculateSellRevenue(fillTypeName, liters)
    return self:getSellPrice(fillTypeName) * liters
end
