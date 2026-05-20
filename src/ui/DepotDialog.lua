-- =========================================================
-- FS25 Fertilizer Depot - Buy/Sell Dialog
-- =========================================================
-- ScreenElement pattern. Two tabs: BUY and SELL.
-- 8 visible rows, paginated through fill type list.

local _depotDialogModDir  = g_currentModDirectory  -- captured at source() time
local _depotDialogModName = g_currentModName
local _depotDialogInstance = nil                  -- local so __index chain can't shadow it

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

local DepotDialog_mt = Class(DepotDialog, ScreenElement)

function DepotDialog.new(depotId)
    local self = ScreenElement.new(nil, DepotDialog_mt)
    self.depotId   = depotId
    self.tab       = DepotDialog.TAB_BUY
    self.pageIndex = 0     -- 0-based offset into fill type list
    self.fillTypes = {}    -- ordered list from SoilFertilizerBridge
    -- Element caches
    self.seasonLabel    = nil
    self.pageLabel      = nil
    self.statusText     = nil
    self.prevPageBtn    = nil
    self.nextPageBtn    = nil
    self.tabBuyBtn      = nil
    self.tabSellBtn     = nil
    self.colTypeHeader  = nil
    self.colStockHeader = nil
    self.colPriceHeader = nil
    self.closeBtn       = nil
    self.rows           = {}  -- [1..ROWS] = {nameEl, stockEl, priceEl, buy1, buy2, buy3}
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
    DepotLogger.info("DepotDialog.show: calling g_gui:showDialog")
    g_gui:showDialog("DepotDialog")
end

-- ─── Lifecycle ───────────────────────────────────────────

function DepotDialog:onGuiSetupFinished()
    DepotDialog:superClass().onGuiSetupFinished(self)

    self.seasonLabel    = self:getDescendantById("seasonLabel")
    self.pageLabel      = self:getDescendantById("pageLabel")
    self.statusText     = self:getDescendantById("statusText")
    self.prevPageBtn    = self:getDescendantById("prevPageBtn")
    self.nextPageBtn    = self:getDescendantById("nextPageBtn")
    self.tabBuyBtn      = self:getDescendantById("tabBuyBtn")
    self.tabSellBtn     = self:getDescendantById("tabSellBtn")
    self.colTypeHeader  = self:getDescendantById("colTypeHeader")
    self.colStockHeader = self:getDescendantById("colStockHeader")
    self.colPriceHeader = self:getDescendantById("colPriceHeader")
    self.closeBtn       = self:getDescendantById("closeButton")

    -- Set static labels via tr() so $l10n_ fallback is overridden correctly
    if self.tabBuyBtn      then self.tabBuyBtn:setText(tr("fd_depot_buy",   "Buy"))          end
    if self.tabSellBtn     then self.tabSellBtn:setText(tr("fd_depot_sell",  "Sell"))         end
    if self.colTypeHeader  then self.colTypeHeader:setText(tr("fd_col_type",  "Fill Type"))   end
    if self.colStockHeader then self.colStockHeader:setText(tr("fd_col_stock", "Depot Stock")) end
    if self.colPriceHeader then self.colPriceHeader:setText(tr("fd_col_price", "Price / 1kL")) end
    if self.closeBtn       then self.closeBtn:setText(tr("fd_depot_close",  "Close"))         end

    -- Cache per-row elements
    for i = 0, DepotDialog.ROWS - 1 do
        local prefix = "row" .. i
        self.rows[i + 1] = {
            nameEl  = self:getDescendantById(prefix .. "name"),
            stockEl = self:getDescendantById(prefix .. "stock"),
            priceEl = self:getDescendantById(prefix .. "price"),
            buy1    = self:getDescendantById(prefix .. "buy1"),
            buy2    = self:getDescendantById(prefix .. "buy2"),
            buy3    = self:getDescendantById(prefix .. "buy3"),
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

function DepotDialog:onClose()
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

-- Show a temporary status message in the footer bar
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
    local key = g_DepotManager.pricing:getSeasonKey()
    local label = tr(key, key)
    local mult  = g_DepotManager.pricing:getSeasonMultiplier()
    local sign  = mult >= 1.0 and "+" or ""
    self.seasonLabel:setText(string.format("%s %s%.0f%%",
        label, sign, (mult - 1.0) * 100))
end

function DepotDialog:refreshBuyTab()
    local total  = #self.fillTypes
    local system = g_DepotManager and g_DepotManager.depotSystem
    local pricing = g_DepotManager and g_DepotManager.pricing

    for slot = 1, DepotDialog.ROWS do
        local ftIdx = self.pageIndex + slot
        local row   = self.rows[slot]
        local ft    = self.fillTypes[ftIdx]

        if ft and row then
            local stored  = system and system:getStorageLevel(self.depotId, ft.name) or 0
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
            if row.stockEl then row.stockEl:setText(stockStr)  end
            if row.priceEl then row.priceEl:setText(priceStr)  end
            if row.buy1    then row.buy1:setVisible(true)       end
            if row.buy2    then row.buy2:setVisible(true)       end
            if row.buy3    then row.buy3:setVisible(true)       end
        else
            -- Empty slot
            self:clearRow(slot)
        end
    end
end

function DepotDialog:refreshSellTab()
    -- Find nearby vehicle's fill levels
    local system  = g_DepotManager and g_DepotManager.depotSystem
    local pricing = g_DepotManager and g_DepotManager.pricing
    local sellTypes = {}  -- {ft=entry, vehicleLiters=n, revenue=n}

    if system and self.depotId then
        for _, ft in ipairs(self.fillTypes) do
            if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
                local vehicle, unitIndex = system:findCompatibleVehicle(
                    self.depotId, ft.fillTypeIndex)
                if vehicle and unitIndex then
                    local level = vehicle:getFillUnitFillLevel(unitIndex)
                    if level and level > 0 then
                        local rev = pricing and pricing:calculateSellRevenue(ft.name, level) or 0
                        table.insert(sellTypes, {
                            ft      = ft,
                            liters  = level,
                            revenue = rev,
                        })
                    end
                end
            end
        end
    end

    -- Display paged sell rows
    for slot = 1, DepotDialog.ROWS do
        local entry = sellTypes[self.pageIndex + slot]
        local row   = self.rows[slot]
        if entry and row then
            local litersStr = string.format("%.0fL", entry.liters)
            local revStr    = string.format("$%.2f", entry.revenue)
            if row.nameEl  then row.nameEl:setText(entry.ft.displayName or entry.ft.name) end
            if row.stockEl then row.stockEl:setText(litersStr) end
            if row.priceEl then row.priceEl:setText(revStr)    end
            if row.buy1    then row.buy1:setVisible(false) end
            if row.buy2    then row.buy2:setVisible(false) end
            -- Use buy3 slot as "Sell All" button (repurposed text)
            if row.buy3 then
                row.buy3:setVisible(true)
                row.buy3:setText(tr("fd_depot_sell_btn", "Sell All"))
            end
        else
            self:clearRow(slot)
        end
    end

    -- Update status line
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
    if row.nameEl  then row.nameEl:setText("")  end
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
    local pageCount = maxPage + 1

    if self.pageLabel then
        self.pageLabel:setText(string.format("%d / %d", curPage + 1, pageCount))
    end
    if self.prevPageBtn then
        self.prevPageBtn:setDisabled(self.pageIndex == 0)
    end
    if self.nextPageBtn then
        self.nextPageBtn:setDisabled(self.pageIndex + DepotDialog.ROWS >= total)
    end
end

function DepotDialog:getSellCount()
    if not g_DepotManager then return 0 end
    local system = g_DepotManager.depotSystem
    local count = 0
    for _, ft in ipairs(self.fillTypes) do
        if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
            local v, u = system:findCompatibleVehicle(self.depotId, ft.fillTypeIndex)
            if v and u and v:getFillUnitFillLevel(u) > 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- ─── Close ───────────────────────────────────────────────

function DepotDialog:onClickClose()
    g_gui:closeDialogByName("DepotDialog")
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
    self.pageIndex = math.min(self.pageIndex + DepotDialog.ROWS,
                              math.max(0, total - 1))
    self:refresh()
end

-- ─── Buy / Sell Actions ──────────────────────────────────

function DepotDialog:executeSell(rowSlot)
    -- In SELL tab, rowSlot refers to the visible sell entry
    -- We need to find the corresponding fill type
    local system = g_DepotManager and g_DepotManager.depotSystem
    if not system then return end
    local count = 0
    local target = self.pageIndex + rowSlot
    for _, ft in ipairs(self.fillTypes) do
        if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
            local v, u = system:findCompatibleVehicle(self.depotId, ft.fillTypeIndex)
            if v and u and v:getFillUnitFillLevel(u) > 0 then
                count = count + 1
                if count == target then
                    local liters = v:getFillUnitFillLevel(u)
                    local farmId = g_localPlayer and g_localPlayer.farmId or 1
                    self:showStatus(string.format("Selling %.0fL %s...",
                        liters, ft.displayName or ft.name))
                    DepotSellEvent.sendToServer(
                        self.depotId, ft.name, ft.fillTypeIndex, liters, farmId)
                    return
                end
            end
        end
    end
end

-- ─── Generated Buy Callbacks (8 rows × 3 quantities) ─────

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

-- Row buy3 doubles as "Sell All" in SELL tab
function DepotDialog:_sellDispatch(rowSlot)
    if self.tab == DepotDialog.TAB_SELL then
        self:executeSell(rowSlot)
    end
end

-- In SELL tab, buy3 (1kL slot) is repurposed as "Sell All".
-- The executeBuy method handles this dispatch.
function DepotDialog:executeBuy(rowSlot, liters)
    if self.tab == DepotDialog.TAB_SELL then
        self:executeSell(rowSlot)
    else
        local ftIdx = self.pageIndex + rowSlot
        local ft    = self.fillTypes[ftIdx]
        if not ft then return end
        local farmId = g_localPlayer and g_localPlayer.farmId or 1
        self:showStatus(string.format("Buying %dL %s...", liters, ft.displayName or ft.name))
        DepotPurchaseEvent.sendToServer(
            self.depotId, ft.name, ft.fillTypeIndex, liters, farmId)
    end
end
