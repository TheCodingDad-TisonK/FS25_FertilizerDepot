-- =========================================================
-- FS25 Fertilizer Depot - Entry Point
-- =========================================================
-- Load order matters: constants first, then logger, then all
-- subsystems, then network events, then UI.

local modDir = g_currentModDirectory

-- Phase 1: Config
source(modDir .. "src/config/Constants.lua")
source(modDir .. "src/DepotLogger.lua")

-- Phase 2: Core systems
source(modDir .. "src/integrations/SoilFertilizerBridge.lua")
source(modDir .. "src/DepotPricing.lua")
source(modDir .. "src/DepotSystem.lua")
source(modDir .. "src/DepotManager.lua")

-- Phase 3: Network
source(modDir .. "src/network/DepotPurchaseEvent.lua")
source(modDir .. "src/network/DepotSellEvent.lua")
source(modDir .. "src/network/DepotSyncEvent.lua")

-- Phase 4: Placeable
source(modDir .. "src/placeable/PlaceableDepot.lua")

-- Phase 5: UI (lazy-loaded on first open, but class must be defined)
source(modDir .. "src/ui/DepotDialog.lua")

-- ─── Mission00 Lifecycle Hooks ───────────────────────────

local function onMissionLoad(mission, ...)
    getfenv(0).g_DepotManager = DepotManager.new()
    g_DepotManager:initialize()
    DepotLogger.info("Mission load complete")
end

local function onMissionLoadFinished(mission, ...)
    -- Register dialog class after GUI system is ready
    DepotDialog.register()
end

local function onMissionUpdate(mission, dt)
    if g_DepotManager then
        g_DepotManager:update(dt)
    end
end

local function onMissionDelete(mission, ...)
    if g_DepotManager then
        g_DepotManager:delete()
        getfenv(0).g_DepotManager = nil
    end
end

Mission00.load                  = Utils.appendedFunction(Mission00.load,                  onMissionLoad)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoadFinished)
FSBaseMission.update            = Utils.appendedFunction(FSBaseMission.update,            onMissionUpdate)
FSBaseMission.delete            = Utils.appendedFunction(FSBaseMission.delete,            onMissionDelete)

-- ─── Console Commands ────────────────────────────────────

addConsoleCommand("SoilDebugDepot", "Toggle FertDepot debug logging",
    "cmdDebugDepot", g_currentModName)

function cmdDebugDepot()
    DepotLogger._debug = not DepotLogger._debug
    print(DepotConstants.LOG_PREFIX .. " Debug: " .. tostring(DepotLogger._debug))
end
