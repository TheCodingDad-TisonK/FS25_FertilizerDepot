-- =========================================================
-- FS25 Fertilizer Depot - Constants
-- =========================================================

DepotConstants = {}

-- Per-fill-type silo capacity in liters
DepotConstants.STORAGE_CAPACITY = 50000

-- Sell-back ratio: players receive this fraction of buy price when selling
DepotConstants.SELL_RATIO = 0.80

-- Seasonal buy price multipliers (period = 1..12 months, grouped into 4 seasons)
-- Spring (months 1-3): 1.15x  |  Summer (4-6): 1.00x  |  Fall (7-9): 0.90x  |  Winter (10-12): 0.85x
DepotConstants.SEASON_MULTIPLIERS = {
    [1] = 1.15, [2] = 1.15, [3] = 1.15,   -- Spring
    [4] = 1.00, [5] = 1.00, [6] = 1.00,   -- Summer
    [7] = 0.90, [8] = 0.90, [9] = 0.90,   -- Fall
    [10] = 0.85, [11] = 0.85, [12] = 0.85, -- Winter
}

-- Default season multiplier (fallback when period is unknown)
DepotConstants.DEFAULT_SEASON_MULTIPLIER = 1.00

-- Fill type definitions with base prices (per liter).
-- Used as fallback when FS25_SoilFertilizer is not installed.
-- When SF IS installed, prices come from the registered FillType economy data.
DepotConstants.VANILLA_FILL_TYPES = {
    { name = "FERTILIZER",       pricePerLiter = 1.60, category = "solid"  },
    { name = "LIQUIDFERTILIZER", pricePerLiter = 1.65, category = "liquid" },
    { name = "LIME",             pricePerLiter = 0.20, category = "solid"  },
    { name = "LIQUIDMANURE",     pricePerLiter = 0.10, category = "liquid" },
    { name = "DIGESTATE",        pricePerLiter = 0.15, category = "liquid" },
    { name = "MANURE",           pricePerLiter = 0.10, category = "solid"  },
}

-- SF fill type names in display order (used when SF IS installed)
DepotConstants.SF_FILL_TYPE_NAMES = {
    -- Liquid nitrogen
    "UAN32", "UAN28", "ANHYDROUS", "STARTER",
    -- Solid granular
    "UREA", "AN", "AMS", "MAP", "DAP", "POTASH", "POLIFOSKA",
    -- Liquid equivalents
    "LIQUID_UREA", "LIQUID_AMS", "LIQUID_MAP", "LIQUID_DAP", "LIQUID_POTASH",
    -- Crop protection
    "INSECTICIDE", "FUNGICIDE",
    -- Organics / amendments
    "GYPSUM", "COMPOST", "BIOSOLIDS", "CHICKEN_MANURE", "PELLETIZED_MANURE",
    -- Liquid lime
    "LIQUIDLIME",
}

-- Physical product ordering (bigBag / liquidTank)
DepotConstants.MAX_PRODUCT_QUANTITY = 5          -- max units per order
DepotConstants.PRODUCT_LITRES_PER_UNIT = 1000    -- standard bigBag/liquidTank capacity in liters

-- Minimum purchase amount (liters)
DepotConstants.MIN_PURCHASE_LITERS = 100

-- Maximum purchase amount per transaction (liters) — prevents abuse
DepotConstants.MAX_PURCHASE_LITERS = 50000

-- Network constants
DepotConstants.NETWORK = {
    -- Minimum liters change before triggering a sync broadcast
    SYNC_THRESHOLD = 100,
}

-- Log prefix
DepotConstants.LOG_PREFIX = "[FertDepot]"

-- Debug default (override via SoilDebugDepot console command)
DepotConstants.DEFAULT_DEBUG = false

-- Delivery system
DepotConstants.DELIVERY = {
    SURCHARGE         = 1.10,   -- total cost multiplier (10% delivery fee)
    MIN_ORDER_LITERS  = 500,    -- min liters short of capacity to include a fill type in the order
    PROXIMITY_PICKUP  = 8.0,    -- metres: on-foot near pickup zone trigger
    TRUCK_DEPOT_RANGE = 25.0,   -- metres: delivery vehicle near depot unload node to enable Complete
    CANCEL_PENALTY    = 0.20,   -- fraction of deliveryCost forfeited when cancelling a PENDING delivery
    TRUCK_XML         = "",  -- delivery truck (disabled: VehicleLoadingData requires a store item, not a raw vehicle XML)
    TRUCK_SPAWN_OFFSET = 8.0,   -- metres offset from unload node so truck doesn't overlap building
}
