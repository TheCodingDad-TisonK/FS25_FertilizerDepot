-- =========================================================
-- FS25 Fertilizer Depot - Buy/Sell Dialog
-- =========================================================
-- MessageDialog pattern (proven: WTListDialog / NPCListDialog).
-- Rules:
--   onClose NEVER named "onClose" (reserved — causes double-call)
--   onCreate required for MessageDialog init
--   Content-area buttons: 3-layer GuiElement container (Bitmap+Text+emptyPanel hit)

local _depotDialogModDir  = g_currentModDirectory  -- captured at source() time
local _depotDialogModName = g_currentModName
local _depotDialogInstance = nil

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[_depotDialogModName]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

---@class DepotDialog
DepotDialog = {}
DepotDialog.ROWS     = 8
DepotDialog.TAB_BUY  = "buy"
DepotDialog.TAB_SELL = "sell"

local DepotDialog_mt = Class(DepotDialog, MessageDialog)

function DepotDialog.new(depotId)
    local self = MessageDialog.new(nil, DepotDialog_mt)
    self.depotId      = depotId
    self.tab          = DepotDialog.TAB_BUY
    self.pageIndex    = 0
    self.fillTypes    = {}
    -- Element caches
    self.seasonLabel    = nil
    self.pageLabel      = nil
    self.statusText     = nil
    self.prevPageBtn    = nil
    self.nextPageBtn    = nil
    self.tabBuyText     = nil   -- Text element inside tab container
    self.tabSellText    = nil
    self.colTypeHeader  = nil
    self.colStockHeader = nil
    self.colPriceHeader = nil
    self.rows           = {}    -- [1..ROWS] = {nameEl, stockEl, priceEl, buy1, buy2, buy3, buy3txt}
    return self
end

-- ─── Registration ────────────────────────────────────────

function DepotDialog.getInstance()
    return _depotDialogInstance
end

function DepotDialog.register()
    if _depotDialogInstance then return end
    _depotDialogInstance = DepotDialog.new(nil)
    DepotLogger.info("DepotDialog.register: loading GUI from %s", _depotDialogModDir)
    g_gui:loadGui(_depotDialogModDir .. "xml/gui/DepotDialog.xml",
        "DepotDialog", _depotDialogInstance)
end

function DepotDialog.show(depotId)
    DepotLogger.info("DepotDialog.show called for depot #%s", tostring(depotId))
    if not _depotDialogInstance then
        DepotDialog.register()
    end
    local dlg = _depotDialogInstance
    dlg.depotId   = depotId
    dlg.tab       = DepotDialog.TAB_BUY
    dlg.pageIndex = 0
    g_gui:showDialog("DepotDialog")
end

-- ─── Lifecycle ───────────────────────────────────────────

function DepotDialog:onCreate()
    local ok, err = pcall(function()
        DepotDialog:superClass().onCreate(self)
    end)
    if not ok then
        DepotLogger.error("DepotDialog:onCreate error: %s", tostring(err))
    end
end

function DepotDialog:onGuiSetupFinished()
    DepotDialog:superClass().onGuiSetupFinished(self)

    self.seasonLabel    = self:getDescendantById("seasonLabel")
    self.pageLabel      = self:getDescendantById("pageLabel")
    self.statusText     = self:getDescendantById("statusText")
    self.prevPageBtn    = self:getDescendantById("prevPageBtn")
    self.nextPageBtn    = self:getDescendantById("nextPageBtn")
    self.tabBuyText     = self:getDescendantById("tabBuyText")
    self.tabSellText    = self:getDescendantById("tabSellText")
    self.colTypeHeader  = self:getDescendantById("colTypeHeader")
    self.colStockHeader = self:getDescendantById("colStockHeader")
    self.colPriceHeader = self:getDescendantById("colPriceHeader")

    -- Set translated static labels
    if self.tabBuyText     then self.tabBuyText:setText(tr("fd_depot_buy",    "Buy"))          end
    if self.tabSellText    then self.tabSellText:setText(tr("fd_depot_sell",   "Sell"))         end
    if self.colTypeHeader  then self.colTypeHeader:setText(tr("fd_col_type",   "Fill Type"))    end
    if self.colStockHeader then self.colStockHeader:setText(tr("fd_col_stock", "Depot Stock"))  end
    if self.colPriceHeader then self.colPriceHeader:setText(tr("fd_col_price", "Price / 1kL")) end

    -- Cache per-row elements (buy3txt = Text inside the buy3 container for sell-mode label)
    for i = 0, DepotDialog.ROWS - 1 do
        local p = "row" .. i
        self.rows[i + 1] = {
            nameEl  = self:getDescendantById(p .. "name"),
            stockEl = self:getDescendantById(p .. "stock"),
            priceEl = self:getDescendantById(p .. "price"),
            buy1    = self:getDescendantById(p .. "buy1"),
            buy2    = self:getDescendantById(p .. "buy2"),
            buy3    = self:getDescendantById(p .. "buy3"),
            buy3txt = self:getDescendantById(p .. "buy3txt"),
        }
    end
end

function DepotDialog:onOpen()
    DepotDialog:superClass().onOpen(self)
    if g_DepotManager then
        self.fillTypes = g_DepotManager.sfBridge:getFillTypeList()
    else
        self.fillTypes = {}
    end
    self:refresh()
end

function DepotDialog:fdOnClose()
    DepotDialog:superClass().onClose(self)
    if g_DepotManager then
        g_DepotManager.activeDialog = nil
    end
end

-- Called by DepotSyncEvent when server pushes new storage state
function DepotDialog:onSyncReceived(depotId)
    if depotId == self.depotId then
        self:refresh()
    end
end

function DepotDialog:showStatus(text)
    if self.statusText then
        self.statusText:setText(text)
    end
end

-- ─── Refresh ─────────────────────────────────────────────

function DepotDialog:refresh()
    self:updateSeasonLabel()
    if self.tab == DepotDialog.TAB_BUY then
        self:refreshBuyTab()
    else
        self:refreshSellTab()
    end
    self:updatePagination()
end

function DepotDialog:updateSeasonLabel()
    if not self.seasonLabel or not g_DepotManager then return end
    local key   = g_DepotManager.pricing:getSeasonKey()
    local label = tr(key, key)
    local mult  = g_DepotManager.pricing:getSeasonMultiplier()
    local sign  = mult >= 1.0 and "+" or ""
    self.seasonLabel:setText(string.format("%s %s%.0f%%", label, sign, (mult - 1.0) * 100))
end

function DepotDialog:refreshBuyTab()
    local system  = g_DepotManager and g_DepotManager.depotSystem
    local pricing = g_DepotManager and g_DepotManager.pricing

    for slot = 1, DepotDialog.ROWS do
        local ftIdx = self.pageIndex + slot
        local row   = self.rows[slot]
        local ft    = self.fillTypes[ftIdx]

        if ft and row then
            local stored   = system and system:getStorageLevel(self.depotId, ft.name) or 0
            local buyPrice = pricing and pricing:getBuyPrice(ft.name) or 0
            local priceStr = string.format("$%.2f/kL", buyPrice * 1000)
            local stockStr
            if stored >= DepotConstants.STORAGE_CAPACITY then
                stockStr = tr("fd_depot_stock_full", "Full")
            elseif stored <= 0 then
                stockStr = tr("fd_depot_stock_stocking", "Stocking")
            else
                stockStr = string.format("%dL", math.floor(stored))
            end

            if row.nameEl  then row.nameEl:setText(ft.displayName or ft.name) end
            if row.stockEl then row.stockEl:setText(stockStr) end
            if row.priceEl then row.priceEl:setText(priceStr) end
            -- Restore 1kL label in case row was previously in sell mode
            if row.buy3txt then row.buy3txt:setText("1kL") end
            if row.buy1    then row.buy1:setVisible(true)  end
            if row.buy2    then row.buy2:setVisible(true)  end
            if row.buy3    then row.buy3:setVisible(true)  end
        else
            self:clearRow(slot)
        end
    end
end

function DepotDialog:refreshSellTab()
    local system  = g_DepotManager and g_DepotManager.depotSystem
    local pricing = g_DepotManager and g_DepotManager.pricing
    local sellTypes = {}

    if system and self.depotId then
        for _, ft in ipairs(self.fillTypes) do
            if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
                local vehicle, unitIndex = system:findCompatibleVehicle(self.depotId, ft.fillTypeIndex, true)
                if vehicle and unitIndex then
                    local level = vehicle:getFillUnitFillLevel(unitIndex)
                    if level and level > 0 then
                        local rev = pricing and pricing:calculateSellRevenue(ft.name, level) or 0
                        table.insert(sellTypes, { ft=ft, liters=level, revenue=rev })
                    end
                end
            end
        end
    end

    for slot = 1, DepotDialog.ROWS do
        local entry = sellTypes[self.pageIndex + slot]
        local row   = self.rows[slot]
        if entry and row then
            local litersStr = string.format("%.0fL", entry.liters)
            local revStr    = string.format("$%.2f", entry.revenue)
            if row.nameEl  then row.nameEl:setText(entry.ft.displayName or entry.ft.name) end
            if row.stockEl then row.stockEl:setText(litersStr) end
            if row.priceEl then row.priceEl:setText(revStr) end
            if row.buy1    then row.buy1:setVisible(false) end
            if row.buy2    then row.buy2:setVisible(false) end
            -- buy3 container repurposed as "Sell All"; set label on its Text child
            if row.buy3txt then row.buy3txt:setText(tr("fd_depot_sell_btn", "Sell All")) end
            if row.buy3    then row.buy3:setVisible(true) end
        else
            self:clearRow(slot)
        end
    end

    if self.statusText then
        if #sellTypes == 0 then
            self.statusText:setText(tr("fd_depot_no_trailer", "No compatible trailer nearby."))
        else
            self.statusText:setText("")
        end
    end
end

function DepotDialog:clearRow(slot)
    local row = self.rows[slot]
    if not row then return end
    if row.nameEl  then row.nameEl:setText("") end
    if row.stockEl then row.stockEl:setText("") end
    if row.priceEl then row.priceEl:setText("") end
    if row.buy1    then row.buy1:setVisible(false) end
    if row.buy2    then row.buy2:setVisible(false) end
    if row.buy3    then row.buy3:setVisible(false) end
end

function DepotDialog:updatePagination()
    local total     = self.tab == DepotDialog.TAB_BUY and #self.fillTypes or self:getSellCount()
    local maxPage   = math.max(0, math.ceil(total / DepotDialog.ROWS) - 1)
    local curPage   = math.floor(self.pageIndex / DepotDialog.ROWS)

    if self.pageLabel then
        self.pageLabel:setText(string.format("%d / %d", curPage + 1, maxPage + 1))
    end
    -- Pagination containers: use setVisible (containers, not Buttons)
    if self.prevPageBtn then
        self.prevPageBtn:setVisible(self.pageIndex > 0)
    end
    if self.nextPageBtn then
        self.nextPageBtn:setVisible(self.pageIndex + DepotDialog.ROWS < total)
    end
end

function DepotDialog:getSellCount()
    if not g_DepotManager then return 0 end
    local system = g_DepotManager.depotSystem
    local count = 0
    for _, ft in ipairs(self.fillTypes) do
        if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
            local v, u = system:findCompatibleVehicle(self.depotId, ft.fillTypeIndex, true)
            if v and u and v:getFillUnitFillLevel(u) > 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- ─── Close ───────────────────────────────────────────────

function DepotDialog:onClickClose()
    self:close()
end

-- ─── Tab Buttons ─────────────────────────────────────────

function DepotDialog:onTabBuy()
    self.tab = DepotDialog.TAB_BUY
    self.pageIndex = 0
    self:refresh()
end

function DepotDialog:onTabSell()
    self.tab = DepotDialog.TAB_SELL
    self.pageIndex = 0
    self:refresh()
end

-- ─── Pagination ──────────────────────────────────────────

function DepotDialog:onPrevPage()
    self.pageIndex = math.max(0, self.pageIndex - DepotDialog.ROWS)
    self:refresh()
end

function DepotDialog:onNextPage()
    local total = self.tab == DepotDialog.TAB_BUY and #self.fillTypes or self:getSellCount()
    self.pageIndex = math.min(self.pageIndex + DepotDialog.ROWS, math.max(0, total - 1))
    self:refresh()
end

-- ─── Buy / Sell Actions ──────────────────────────────────

function DepotDialog:executeSell(rowSlot)
    local system = g_DepotManager and g_DepotManager.depotSystem
    if not system then return end
    local count  = 0
    local target = self.pageIndex + rowSlot
    for _, ft in ipairs(self.fillTypes) do
        if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
            local v, u = system:findCompatibleVehicle(self.depotId, ft.fillTypeIndex, true)
            if v and u and v:getFillUnitFillLevel(u) > 0 then
                count = count + 1
                if count == target then
                    local liters = v:getFillUnitFillLevel(u)
                    local farmId = g_localPlayer and g_localPlayer.farmId or 1
                    self:showStatus(string.format("Selling %.0fL %s...", liters, ft.displayName or ft.name))
                    DepotSellEvent.sendToServer(self.depotId, ft.name, ft.fillTypeIndex, liters, farmId)
                    return
                end
            end
        end
    end
end

function DepotDialog:executeBuy(rowSlot, liters)
    if self.tab == DepotDialog.TAB_SELL then
        self:executeSell(rowSlot)
        return
    end
    local ftIdx = self.pageIndex + rowSlot
    local ft    = self.fillTypes[ftIdx]
    if not ft then return end
    local farmId = g_localPlayer and g_localPlayer.farmId or 1
    self:showStatus(string.format("Buying %dL %s...", liters, ft.displayName or ft.name))
    DepotPurchaseEvent.sendToServer(self.depotId, ft.name, ft.fillTypeIndex, liters, farmId)
end

-- ─── Generated Buy Callbacks (8 rows x 3 quantities) ─────

function DepotDialog:onBuy0_100()  self:executeBuy(1, 100)  end
function DepotDialog:onBuy0_500()  self:executeBuy(1, 500)  end
function DepotDialog:onBuy0_1000() self:executeBuy(1, 1000) end

function DepotDialog:onBuy1_100()  self:executeBuy(2, 100)  end
function DepotDialog:onBuy1_500()  self:executeBuy(2, 500)  end
function DepotDialog:onBuy1_1000() self:executeBuy(2, 1000) end

function DepotDialog:onBuy2_100()  self:executeBuy(3, 100)  end
function DepotDialog:onBuy2_500()  self:executeBuy(3, 500)  end
function DepotDialog:onBuy2_1000() self:executeBuy(3, 1000) end

function DepotDialog:onBuy3_100()  self:executeBuy(4, 100)  end
function DepotDialog:onBuy3_500()  self:executeBuy(4, 500)  end
function DepotDialog:onBuy3_1000() self:executeBuy(4, 1000) end

function DepotDialog:onBuy4_100()  self:executeBuy(5, 100)  end
function DepotDialog:onBuy4_500()  self:executeBuy(5, 500)  end
function DepotDialog:onBuy4_1000() self:executeBuy(5, 1000) end

function DepotDialog:onBuy5_100()  self:executeBuy(6, 100)  end
function DepotDialog:onBuy5_500()  self:executeBuy(6, 500)  end
function DepotDialog:onBuy5_1000() self:executeBuy(6, 1000) end

function DepotDialog:onBuy6_100()  self:executeBuy(7, 100)  end
function DepotDialog:onBuy6_500()  self:executeBuy(7, 500)  end
function DepotDialog:onBuy6_1000() self:executeBuy(7, 1000) end

function DepotDialog:onBuy7_100()  self:executeBuy(8, 100)  end
function DepotDialog:onBuy7_500()  self:executeBuy(8, 500)  end
function DepotDialog:onBuy7_1000() self:executeBuy(8, 1000) end
