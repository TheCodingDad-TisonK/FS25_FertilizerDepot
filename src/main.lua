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
source(modDir .. "src/network/DepotSiloFillEvent.lua")
source(modDir .. "src/network/DepotSyncEvent.lua")
source(modDir .. "src/network/DepotSettingsEvent.lua")
source(modDir .. "src/network/DepotProductOrderEvent.lua")

-- Phase 4: Placeables
source(modDir .. "src/placeable/PlaceableDepot.lua")
source(modDir .. "src/placeable/PlaceableSilo.lua")

-- Phase 5: UI (lazy-loaded on first open, but class must be defined)
source(modDir .. "src/ui/DepotDialog.lua")
source(modDir .. "src/ui/DepotSettingsDialog.lua")

-- ─── Mission00 Lifecycle Hooks ───────────────────────────

local function onMissionLoad(mission, ...)
    getfenv(0).g_DepotManager = DepotManager.new()
    g_DepotManager:initialize()

    -- Load settings from our own XML file (same pattern as FuelCosts, SoilFertilizer).
    -- FSCareerMissionInfo.loadFromXMLFile fires before g_DepotManager exists, so we
    -- read directly here where the manager is guaranteed to be present.
    local missionInfo = mission and mission.missionInfo
    if missionInfo and missionInfo.savegameDirectory then
        local path = missionInfo.savegameDirectory .. "/FS25_FertilizerDepot.xml"
        local xmlFile = XMLFile.load("depotSettingsLoad", path)
        if xmlFile then
            g_DepotManager.settings:loadFromXML(xmlFile, "fertilizerDepot.settings")
            DepotLogger._debug = g_DepotManager.settings.debugLogging
            xmlFile:delete()
            DepotLogger.info("Settings loaded from savegame")
        end
    end
    DepotLogger.info("Mission load complete")
end

local function onMissionLoadFinished(mission, ...)
    if not g_DepotManager then return end
    -- SF global is now available if installed
    g_DepotManager.sfBridge:invalidateCache()
    DepotLogger.info("Post-load: SF installed: %s",
        tostring(g_DepotManager.sfBridge:isInstalled()))

    -- Register Shift+D settings hotkey in PLAYER context.
    -- Pattern mirrors FS25_SoilFertilizer:SoilFertilityManager.lua exactly.
    if PlayerInputComponent and PlayerInputComponent.registerActionEvents then
        local origRegister = PlayerInputComponent.registerActionEvents
        PlayerInputComponent.registerActionEvents = function(inputComp, ...)
            origRegister(inputComp, ...)

            -- Only register for the local (owning) player, not networked players
            if not (inputComp.player and inputComp.player.isOwner) then return end
            -- Guard against double-registration across level reloads
            if g_DepotManager and g_DepotManager._settingsEventId then return end
            if not g_DepotManager then return end

            if not InputAction.FD_OPEN_SETTINGS then
                DepotLogger.warning("InputAction.FD_OPEN_SETTINGS is nil — check modDesc <actions>")
                return
            end

            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
            local ok, id = g_inputBinding:registerActionEvent(
                InputAction.FD_OPEN_SETTINGS, g_DepotManager,
                g_DepotManager.openSettingsDialog, false, true, false, true)
            if ok and id then
                g_DepotManager._settingsEventId = id
                g_inputBinding:setActionEventTextVisibility(id, false)
                DepotLogger.info("Shift+D (FD_OPEN_SETTINGS) registered in PLAYER context")
            else
                DepotLogger.warning("Shift+D registration failed — registerActionEvent returned false")
            end
            g_inputBinding:endActionEventsModification()
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

-- Save settings to our own XML file (same pattern as FuelCosts / SoilFertilizer).
-- The xmlFile argument from FSCareerMissionInfo.saveToXMLFile is always nil for mods;
-- we write directly to savegameDirectory instead.
local function onSaveToXML(missionInfo, xmlFile, ...)
    if not g_DepotManager then return end
    if not missionInfo or not missionInfo.savegameDirectory then
        DepotLogger.warning("onSaveToXML: savegameDirectory not available — skipping")
        return
    end
    local path = missionInfo.savegameDirectory .. "/FS25_FertilizerDepot.xml"
    local outFile = XMLFile.create("depotSettingsSave", path, "fertilizerDepot")
    if not outFile then
        DepotLogger.warning("onSaveToXML: could not create XML file")
        return
    end
    g_DepotManager.settings:saveToXML(outFile, "fertilizerDepot.settings")
    outFile:save()
    outFile:delete()
    DepotLogger.info("Settings saved to %s", path)
end

-- Send settings to a joining client so they start with the correct server values
local function onSendInitialClientState(mission, connection, ...)
    if not g_DepotManager then return end
    DepotSettingsSyncEvent.sendToClient(connection)
end

-- PREPEND so g_DepotManager exists before Mission00.load loads savegame placeables.
-- appendedFunction would create it AFTER onPostFinalizePlacement fires → depotId never set.
Mission00.load                        = Utils.prependedFunction(Mission00.load,                        onMissionLoad)
Mission00.loadMission00Finished       = Utils.appendedFunction(Mission00.loadMission00Finished,       onMissionLoadFinished)
FSBaseMission.update                  = Utils.appendedFunction(FSBaseMission.update,                  onMissionUpdate)
FSBaseMission.delete                  = Utils.appendedFunction(FSBaseMission.delete,                  onMissionDelete)
FSBaseMission.sendInitialClientState  = Utils.appendedFunction(FSBaseMission.sendInitialClientState,  onSendInitialClientState)
FSCareerMissionInfo.saveToXMLFile     = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile,     onSaveToXML)

-- ─── Console Commands ────────────────────────────────────

addConsoleCommand("SoilDebugDepot", "Toggle FertDepot debug logging",
    "cmdDebugDepot", g_currentModName)
addConsoleCommand("FDFillStock",  "Fill all depot storage to max capacity [depotId optional]",
    "cmdFDFillStock", g_currentModName)
addConsoleCommand("FDEmptyStock", "Empty all depot storage [depotId optional]",
    "cmdFDEmptyStock", g_currentModName)

function cmdDebugDepot()
    DepotLogger._debug = not DepotLogger._debug
    print(DepotConstants.LOG_PREFIX .. " Debug: " .. tostring(DepotLogger._debug))
end

-- Helper: iterate depots, optionally filtered to a single depotId
local function _iterateDepots(targetId, fn)
    if not g_DepotManager then
        print(DepotConstants.LOG_PREFIX .. " DepotManager not ready")
        return 0
    end
    local count = 0
    for id, placeable in pairs(g_DepotManager.depots) do
        if targetId == nil or id == targetId then
            fn(id, placeable)
            count = count + 1
        end
    end
    return count
end

function cmdFDFillStock(depotIdArg)
    if not g_server then
        print(DepotConstants.LOG_PREFIX .. " FDFillStock: server only")
        return
    end
    local targetId = depotIdArg and tonumber(depotIdArg) or nil
    local fillTypes = g_DepotManager and g_DepotManager.sfBridge:getFillTypeList() or {}
    local cap = (g_DepotManager and g_DepotManager.settings.storageCapacity)
                or DepotConstants.STORAGE_CAPACITY
    local depotCount = _iterateDepots(targetId, function(id, _)
        for _, ft in ipairs(fillTypes) do
            g_DepotManager.depotSystem:setStorageLevel(id, ft.name, cap)
        end
        g_DepotManager:broadcastSync(id)
        DepotLogger.info("FDFillStock: depot #%d filled (%.0f types × %.0fL)", id, #fillTypes, cap)
    end)
    print(string.format("%s FDFillStock: filled %d depot(s) to %.0fL each type",
        DepotConstants.LOG_PREFIX, depotCount, cap))
end

function cmdFDEmptyStock(depotIdArg)
    if not g_server then
        print(DepotConstants.LOG_PREFIX .. " FDEmptyStock: server only")
        return
    end
    local targetId = depotIdArg and tonumber(depotIdArg) or nil
    local fillTypes = g_DepotManager and g_DepotManager.sfBridge:getFillTypeList() or {}
    local depotCount = _iterateDepots(targetId, function(id, _)
        for _, ft in ipairs(fillTypes) do
            g_DepotManager.depotSystem:setStorageLevel(id, ft.name, 0)
        end
        g_DepotManager:broadcastSync(id)
        DepotLogger.info("FDEmptyStock: depot #%d emptied", id)
    end)
    print(string.format("%s FDEmptyStock: emptied %d depot(s)",
        DepotConstants.LOG_PREFIX, depotCount))
end
