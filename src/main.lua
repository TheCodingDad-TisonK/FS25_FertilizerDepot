-- =========================================================
-- FS25 Fertilizer Depot - Entry Point
-- =========================================================
-- Load order matters: constants first, then logger, then all
-- subsystems, then network events, then UI.

local modDir = g_currentModDirectory

-- Phase 1: Config
source(modDir .. "src/config/Constants.lua")
source(modDir .. "src/config/DepotSettings.lua")
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
source(modDir .. "src/network/DepotSettingsEvent.lua")

-- Phase 4: Placeable
source(modDir .. "src/placeable/PlaceableDepot.lua")

-- Phase 5: UI (lazy-loaded on first open, but class must be defined)
source(modDir .. "src/ui/DepotDialog.lua")
source(modDir .. "src/ui/DepotSettingsDialog.lua")

-- ─── Mission00 Lifecycle Hooks ───────────────────────────

local function onMissionLoad(mission, ...)
    getfenv(0).g_DepotManager = DepotManager.new()
    g_DepotManager:initialize()
    DepotLogger.info("Mission load complete")
end

local function onMissionLoadFinished(mission, ...)
    if not g_DepotManager then return end
    -- SF global is now available if installed
    g_DepotManager.sfBridge:invalidateCache()
    DepotLogger.info("Post-load: SF installed: %s",
        tostring(g_DepotManager.sfBridge:isInstalled()))

    -- Register Shift+D settings hotkey in both PLAYER and VEHICLE contexts.
    -- Follows the same PlayerInputComponent hook pattern as FS25_SoilFertilizer.
    if PlayerInputComponent and PlayerInputComponent.registerActionEvents then
        local origRegister = PlayerInputComponent.registerActionEvents
        PlayerInputComponent.registerActionEvents = function(inputComp, ...)
            origRegister(inputComp, ...)
            if g_inputBinding then
                g_inputBinding:beginActionEventsModification(
                    PlayerInputComponent.INPUT_CONTEXT_NAME)
                local ok, id = g_inputBinding:registerActionEvent(
                    InputAction.FD_OPEN_SETTINGS, g_DepotManager,
                    g_DepotManager.openSettingsDialog, false, true, false, true)
                if ok then
                    g_inputBinding:setActionEventText(id,
                        g_i18n:getText("fd_settings_title"))
                    g_inputBinding:setActionEventTextVisibility(id, false)
                end
                g_inputBinding:endActionEventsModification()
                DepotLogger.debug("Shift+D registered in PLAYER context")
            end
        end
    end
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

-- Save settings alongside savegame
local function onSaveToXML(missionInfo, xmlFile, ...)
    if g_DepotManager then
        g_DepotManager.settings:saveToXML(xmlFile, "fertilizerDepot.settings")
        DepotLogger.debug("Settings saved")
    end
end

-- PREPEND so g_DepotManager exists before Mission00.load loads savegame placeables.
-- appendedFunction would create it AFTER onPostFinalizePlacement fires → depotId never set.
Mission00.load                        = Utils.prependedFunction(Mission00.load,                        onMissionLoad)
Mission00.loadMission00Finished       = Utils.appendedFunction(Mission00.loadMission00Finished,       onMissionLoadFinished)
FSBaseMission.update                  = Utils.appendedFunction(FSBaseMission.update,                  onMissionUpdate)
FSBaseMission.delete                  = Utils.appendedFunction(FSBaseMission.delete,                  onMissionDelete)
FSCareerMissionInfo.saveToXMLFile     = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile,     onSaveToXML)

-- ─── Console Commands ────────────────────────────────────

addConsoleCommand("SoilDebugDepot", "Toggle FertDepot debug logging",
    "cmdDebugDepot", g_currentModName)

function cmdDebugDepot()
    DepotLogger._debug = not DepotLogger._debug
    print(DepotConstants.LOG_PREFIX .. " Debug: " .. tostring(DepotLogger._debug))
end
