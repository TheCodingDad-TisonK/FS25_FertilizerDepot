-- =========================================================
-- FS25 Fertilizer Depot - Settings Dialog
-- =========================================================
-- Opened via Shift+D hotkey. Admin-only in multiplayer.
-- Uses MultiTextOptionElement for each setting (cycle presets).

local _depotSettingsModDir  = g_currentModDirectory  -- captured at source() time
local _depotSettingsModName = g_currentModName
local _depotSettingsInstance = nil                  -- local so __index chain can't shadow it

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[_depotSettingsModName]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

---@class DepotSettingsDialog
DepotSettingsDialog = {}

local DepotSettingsDialog_mt = Class(DepotSettingsDialog, MessageDialog)

function DepotSettingsDialog.new()
    local self = MessageDialog.new(nil, DepotSettingsDialog_mt)
    -- Element caches
    self.optSeasonalPricing  = nil
    self.optStorageCapacity  = nil
    self.optSellRatio        = nil
    self.optBuyMultiplier    = nil
    self.adminBadge          = nil
    self.isOpen              = false
    return self
end

-- ─── Registration ────────────────────────────────────────

function DepotSettingsDialog.register()
    if _depotSettingsInstance then return end
    _depotSettingsInstance = DepotSettingsDialog.new()
    DepotLogger.info("DepotSettingsDialog.register: loading GUI from %s", _depotSettingsModDir)
    g_gui:loadGui(_depotSettingsModDir .. "xml/gui/DepotSettingsDialog.xml",
        "DepotSettingsDialog", _depotSettingsInstance)
end

function DepotSettingsDialog.show()
    DepotLogger.info("DepotSettingsDialog.show called")
    if not _depotSettingsInstance then
        DepotSettingsDialog.register()
    end
    g_gui:showDialog("DepotSettingsDialog")
end

function DepotSettingsDialog.refreshIfOpen()
    if _depotSettingsInstance and _depotSettingsInstance.isOpen then
        _depotSettingsInstance:refresh()
    end
end

-- ─── Lifecycle ───────────────────────────────────────────

function DepotSettingsDialog:onCreate()
    local ok, err = pcall(function()
        DepotSettingsDialog:superClass().onCreate(self)
    end)
    if not ok then
        DepotLogger.error("DepotSettingsDialog:onCreate error: %s", tostring(err))
    end
end

function DepotSettingsDialog:onGuiSetupFinished()
    DepotSettingsDialog:superClass().onGuiSetupFinished(self)
    self.optSeasonalPricing = self:getDescendantById("optSeasonalPricing")
    self.optStorageCapacity = self:getDescendantById("optStorageCapacity")
    self.optSellRatio       = self:getDescendantById("optSellRatio")
    self.optBuyMultiplier   = self:getDescendantById("optBuyMultiplier")
    self.adminBadge         = self:getDescendantById("adminBadge")

    -- Populate option lists
    if self.optSeasonalPricing then
        self.optSeasonalPricing:setTexts({
            tr("fd_settings_off", "OFF"),
            tr("fd_settings_on",  "ON"),
        })
    end
    if self.optStorageCapacity then
        local labels = {}
        for _, v in ipairs(DepotSettings.CAPACITY_OPTIONS) do
            table.insert(labels, string.format("%s L", tostring(math.floor(v / 1000)) .. "k"))
        end
        self.optStorageCapacity:setTexts(labels)
    end
    if self.optSellRatio then
        local labels = {}
        for _, v in ipairs(DepotSettings.SELL_RATIO_OPTIONS) do
            table.insert(labels, string.format("%d%%", math.floor(v * 100)))
        end
        self.optSellRatio:setTexts(labels)
    end
    if self.optBuyMultiplier then
        local labels = {}
        for _, v in ipairs(DepotSettings.BUY_MULT_OPTIONS) do
            table.insert(labels, string.format("%.2f×", v))
        end
        self.optBuyMultiplier:setTexts(labels)
    end
end

function DepotSettingsDialog:onOpen()
    DepotSettingsDialog:superClass().onOpen(self)
    self.isOpen = true
    self:refresh()
end

function DepotSettingsDialog:fdSettingsOnClose()
    DepotSettingsDialog:superClass().onClose(self)
    self.isOpen = false
end

-- ─── Refresh ─────────────────────────────────────────────

function DepotSettingsDialog:refresh()
    if not g_DepotManager then return end
    local s = g_DepotManager.settings
    local isAdmin = g_currentMission.isMasterUser or g_server ~= nil

    if self.adminBadge then
        self.adminBadge:setVisible(not isAdmin)
    end

    if self.optSeasonalPricing then
        self.optSeasonalPricing:setState(s.seasonalPricing and 2 or 1)
        self.optSeasonalPricing:setDisabled(not isAdmin)
    end
    if self.optStorageCapacity then
        self.optStorageCapacity:setState(s:getCapacityIndex())
        self.optStorageCapacity:setDisabled(not isAdmin)
    end
    if self.optSellRatio then
        self.optSellRatio:setState(s:getSellRatioIndex())
        self.optSellRatio:setDisabled(not isAdmin)
    end
    if self.optBuyMultiplier then
        self.optBuyMultiplier:setState(s:getBuyMultiplierIndex())
        self.optBuyMultiplier:setDisabled(not isAdmin)
    end
end

-- ─── Option Callbacks ────────────────────────────────────

function DepotSettingsDialog:onSeasonalPricingChanged(state)
    local value = (state == 2)  -- 1=OFF, 2=ON
    DepotSettingsEvent.sendToServer("seasonalPricing", tostring(value))
end

function DepotSettingsDialog:onStorageCapacityChanged(state)
    local value = DepotSettings.CAPACITY_OPTIONS[state]
    if value then
        DepotSettingsEvent.sendToServer("storageCapacity", tostring(value))
    end
end

function DepotSettingsDialog:onSellRatioChanged(state)
    local value = DepotSettings.SELL_RATIO_OPTIONS[state]
    if value then
        DepotSettingsEvent.sendToServer("sellRatio", tostring(value))
    end
end

function DepotSettingsDialog:onBuyMultiplierChanged(state)
    local value = DepotSettings.BUY_MULT_OPTIONS[state]
    if value then
        DepotSettingsEvent.sendToServer("buyMultiplier", tostring(value))
    end
end

function DepotSettingsDialog:onResetDefaults()
    if not (g_currentMission.isMasterUser or g_server ~= nil) then return end
    DepotSettingsEvent.sendToServer("seasonalPricing", tostring(DepotSettings.DEFAULTS.seasonalPricing))
    DepotSettingsEvent.sendToServer("storageCapacity", tostring(DepotSettings.DEFAULTS.storageCapacity))
    DepotSettingsEvent.sendToServer("sellRatio",       tostring(DepotSettings.DEFAULTS.sellRatio))
    DepotSettingsEvent.sendToServer("buyMultiplier",   tostring(DepotSettings.DEFAULTS.buyMultiplier))
end

function DepotSettingsDialog:onCloseSettings()
    self:close()
end
