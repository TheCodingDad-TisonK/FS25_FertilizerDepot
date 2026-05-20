-- =========================================================
-- FS25 Fertilizer Depot - Buy/Sell Dialog
-- =========================================================

local _depotDialogModDir  = g_currentModDirectory
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
DepotDialog.ROWS        = 8
DepotDialog.TAB_BUY     = "buy"
DepotDialog.TAB_SELL    = "sell"
DepotDialog.ORDER_STEP  = 500
DepotDialog.ORDER_MIN   = 500
DepotDialog.ORDER_MAX   = 50000

local DepotDialog_mt = Class(DepotDialog, MessageDialog)

function DepotDialog.new(depotId)
    local self = MessageDialog.new(nil, DepotDialog_mt)
    self.depotId          = depotId
    self.tab              = DepotDialog.TAB_BUY
    self.pageIndex        = 0
    self.fillTypes        = {}
    self.selectedFillType = nil
    self.orderAmount      = 1000

    -- Element caches
    self.seasonLabel      = nil
    self.pageLabel        = nil
    self.statusText       = nil
    self.prevPageBtn      = nil
    self.nextPageBtn      = nil
    self.colTypeHeader    = nil
    self.colStockHeader   = nil
    self.colPriceHeader   = nil
    self.preOrderDivider  = nil
    self.preOrderRow      = nil
    self.selectedTypeName = nil
    self.amountDisplay    = nil

    -- [1..ROWS] = {nameEl, stockEl, priceEl, actionBtn, actionTxt}
    self.rows = {}
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
    dlg.depotId        = depotId
    dlg.tab            = DepotDialog.TAB_BUY
    dlg.pageIndex      = 0
    dlg.selectedFillType = nil
    dlg.orderAmount    = 1000
    g_gui:showDialog("DepotDialog")
end

-- ─── Lifecycle ───────────────────────────────────────────

function DepotDialog:onCreate()
    local ok, err = pcall(function() DepotDialog:superClass().onCreate(self) end)
    if not ok then DepotLogger.error("DepotDialog:onCreate error: %s", tostring(err)) end
end

function DepotDialog:onGuiSetupFinished()
    DepotDialog:superClass().onGuiSetupFinished(self)

    self.seasonLabel     = self:getDescendantById("seasonLabel")
    self.pageLabel       = self:getDescendantById("pageLabel")
    self.statusText      = self:getDescendantById("statusText")
    self.prevPageBtn     = self:getDescendantById("prevPageBtn")
    self.nextPageBtn     = self:getDescendantById("nextPageBtn")
    self.colTypeHeader   = self:getDescendantById("colTypeHeader")
    self.colStockHeader  = self:getDescendantById("colStockHeader")
    self.colPriceHeader  = self:getDescendantById("colPriceHeader")
    self.preOrderDivider = self:getDescendantById("preOrderDivider")
    self.preOrderRow     = self:getDescendantById("preOrderRow")
    self.selectedTypeName = self:getDescendantById("selectedTypeName")
    self.amountDisplay   = self:getDescendantById("amountDisplay")

    if self.colTypeHeader   then self.colTypeHeader:setText(tr("fd_col_type",   "Fill Type"))    end
    if self.colStockHeader  then self.colStockHeader:setText(tr("fd_col_stock", "Depot Stock"))  end
    if self.colPriceHeader  then self.colPriceHeader:setText(tr("fd_col_price", "Price / 1kL")) end

    for i = 0, DepotDialog.ROWS - 1 do
        local p = "row" .. i
        self.rows[i + 1] = {
            nameEl    = self:getDescendantById(p .. "name"),
            stockEl   = self:getDescendantById(p .. "stock"),
            priceEl   = self:getDescendantById(p .. "price"),
            actionBtn = self:getDescendantById(p .. "action"),
            actionTxt = self:getDescendantById(p .. "actionTxt"),
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
    self:_syncPreOrderVisibility()
    self:refresh()
end

function DepotDialog:fdOnClose()
    DepotDialog:superClass().onClose(self)
    if g_DepotManager then
        g_DepotManager.activeDialog = nil
    end
end

function DepotDialog:onSyncReceived(depotId)
    if depotId == self.depotId then self:refresh() end
end

function DepotDialog:showStatus(text)
    if self.statusText then self.statusText:setText(text) end
end

-- ─── Tab Switching ───────────────────────────────────────

function DepotDialog:onTabBuy()
    self.tab = DepotDialog.TAB_BUY
    self.pageIndex = 0
    self:_syncPreOrderVisibility()
    self:refresh()
end

function DepotDialog:onTabSell()
    self.tab = DepotDialog.TAB_SELL
    self.pageIndex = 0
    self:_syncPreOrderVisibility()
    self:refresh()
end

function DepotDialog:_syncPreOrderVisibility()
    local show = (self.tab == DepotDialog.TAB_BUY)
    if self.preOrderDivider then self.preOrderDivider:setVisible(show) end
    if self.preOrderRow     then self.preOrderRow:setVisible(show) end
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

            -- Highlight if this row is the currently selected type
            local isSelected = self.selectedFillType and self.selectedFillType.name == ft.name
            if row.actionTxt then
                row.actionTxt:setText(isSelected and "Selected" or tr("fd_depot_select_btn", "Select"))
            end
            if row.actionBtn then row.actionBtn:setVisible(true) end
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
            if row.nameEl   then row.nameEl:setText(entry.ft.displayName or entry.ft.name) end
            if row.stockEl  then row.stockEl:setText(litersStr) end
            if row.priceEl  then row.priceEl:setText(revStr) end
            if row.actionTxt then row.actionTxt:setText(tr("fd_depot_sell_btn", "Sell All")) end
            if row.actionBtn then row.actionBtn:setVisible(true) end
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
    if row.nameEl   then row.nameEl:setText("") end
    if row.stockEl  then row.stockEl:setText("") end
    if row.priceEl  then row.priceEl:setText("") end
    if row.actionBtn then row.actionBtn:setVisible(false) end
end

function DepotDialog:updatePagination()
    local total   = self.tab == DepotDialog.TAB_BUY and #self.fillTypes or self:getSellCount()
    local maxPage = math.max(0, math.ceil(total / DepotDialog.ROWS) - 1)
    local curPage = math.floor(self.pageIndex / DepotDialog.ROWS)

    if self.pageLabel then
        self.pageLabel:setText(string.format("%d / %d", curPage + 1, maxPage + 1))
    end
    if self.prevPageBtn then self.prevPageBtn:setVisible(self.pageIndex > 0) end
    if self.nextPageBtn then self.nextPageBtn:setVisible(self.pageIndex + DepotDialog.ROWS < total) end
end

function DepotDialog:getSellCount()
    if not g_DepotManager then return 0 end
    local system = g_DepotManager.depotSystem
    local count = 0
    for _, ft in ipairs(self.fillTypes) do
        if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
            local v, u = system:findCompatibleVehicle(self.depotId, ft.fillTypeIndex, true)
            if v and u and v:getFillUnitFillLevel(u) > 0 then count = count + 1 end
        end
    end
    return count
end

-- ─── Pre-order Actions ───────────────────────────────────

function DepotDialog:onAmountMinus()
    self.orderAmount = math.max(DepotDialog.ORDER_MIN, self.orderAmount - DepotDialog.ORDER_STEP)
    if self.amountDisplay then
        self.amountDisplay:setText(string.format("%dL", self.orderAmount))
    end
end

function DepotDialog:onAmountPlus()
    self.orderAmount = math.min(DepotDialog.ORDER_MAX, self.orderAmount + DepotDialog.ORDER_STEP)
    if self.amountDisplay then
        self.amountDisplay:setText(string.format("%dL", self.orderAmount))
    end
end

function DepotDialog:onConfirmOrder()
    if not self.selectedFillType then
        self:showStatus(tr("fd_depot_select_first", "Select a fill type first."))
        return
    end
    local farmId = g_localPlayer and g_localPlayer.farmId or 1
    if g_DepotManager then
        g_DepotManager:setPendingOrder(
            farmId, self.depotId,
            self.selectedFillType.name,
            self.selectedFillType.fillTypeIndex,
            self.orderAmount,
            self.selectedFillType.displayName or self.selectedFillType.name)
    end
    self:showStatus(string.format(
        tr("fd_depot_order_set", "Order set: %s %.0fL — drive to silo to collect."),
        self.selectedFillType.displayName or self.selectedFillType.name,
        self.orderAmount))
end

-- ─── Row Action (Select for Buy, Sell All for Sell) ──────

function DepotDialog:onRowAction(rowSlot)
    if self.tab == DepotDialog.TAB_SELL then
        self:executeSell(rowSlot)
    else
        self:selectRow(rowSlot)
    end
end

function DepotDialog:selectRow(rowSlot)
    local ftIdx = self.pageIndex + rowSlot
    local ft    = self.fillTypes[ftIdx]
    if not ft then return end
    self.selectedFillType = ft
    self.orderAmount      = 1000
    if self.selectedTypeName then
        self.selectedTypeName:setText(ft.displayName or ft.name)
    end
    if self.amountDisplay then
        self.amountDisplay:setText(string.format("%dL", self.orderAmount))
    end
    self:showStatus("")
    -- Refresh buy rows so the selected row shows "Selected"
    self:refreshBuyTab()
end

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

-- ─── Close ───────────────────────────────────────────────

function DepotDialog:onClickClose()
    self:close()
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

-- ─── Generated Row Callbacks ─────────────────────────────

function DepotDialog:onAction0() self:onRowAction(1) end
function DepotDialog:onAction1() self:onRowAction(2) end
function DepotDialog:onAction2() self:onRowAction(3) end
function DepotDialog:onAction3() self:onRowAction(4) end
function DepotDialog:onAction4() self:onRowAction(5) end
function DepotDialog:onAction5() self:onRowAction(6) end
function DepotDialog:onAction6() self:onRowAction(7) end
function DepotDialog:onAction7() self:onRowAction(8) end
