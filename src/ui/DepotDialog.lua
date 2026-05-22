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
        -- FS25 returns "Missing 'key' in l10n_XX.xml" for unknown keys instead of throwing
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key)
           and not text:find("^Missing '") then
            return text
        end
    end
    return fallback or key
end

---@class DepotDialog
DepotDialog = {}
DepotDialog.ROWS        = 8
DepotDialog.TAB_BUY      = "buy"
DepotDialog.TAB_SELL     = "sell"
DepotDialog.TAB_PRODUCTS = "products"
DepotDialog.TAB_ORDER    = "order"
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

    -- Products tab state
    self.productFillTypes   = {}
    self.selectedProduct    = nil
    self.productQuantity    = 1

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

    -- Products order row elements
    self.productsOrderRow     = nil
    self.prodSelectedName     = nil
    self.prodQtyDisplay       = nil
    self.prodTotalPrice       = nil

    -- Order tab elements
    self.orderPanel           = nil
    self.orderCostText        = nil
    self.orderActionBtn       = nil
    self.orderActionTxt       = nil

    -- [1..ROWS] = {nameEl, stockEl, priceEl, actionBtn, actionTxt}
    self.rows = {}
    -- Cached sell list built each refresh: [{ft, liters, revenue}, ...]
    self.sellList = {}
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
    dlg.depotId          = depotId
    dlg.tab              = DepotDialog.TAB_BUY
    dlg.pageIndex        = 0
    dlg.selectedFillType = nil
    dlg.orderAmount      = 1000
    dlg.selectedProduct  = nil
    dlg.productQuantity  = 1
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
    self.preOrderDivider  = self:getDescendantById("preOrderDivider")
    self.preOrderRow      = self:getDescendantById("preOrderRow")
    self.selectedTypeName = self:getDescendantById("selectedTypeName")
    self.amountDisplay    = self:getDescendantById("amountDisplay")

    self.productsOrderRow = self:getDescendantById("productsOrderRow")
    self.prodSelectedName = self:getDescendantById("prodSelectedName")
    self.prodQtyDisplay   = self:getDescendantById("prodQtyDisplay")
    self.prodTotalPrice   = self:getDescendantById("prodTotalPrice")

    self.orderPanel     = self:getDescendantById("orderPanel")
    self.orderCostText  = self:getDescendantById("orderCostText")
    self.orderActionBtn = self:getDescendantById("orderActionBtn")
    self.orderActionTxt = self:getDescendantById("orderActionTxt")

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
        self.fillTypes       = g_DepotManager.sfBridge:getFillTypeList()
        self.productFillTypes = g_DepotManager.sfBridge:getProductFillTypeList()
    else
        self.fillTypes        = {}
        self.productFillTypes = {}
    end
    self:_syncTabSections()
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
    self:_syncTabSections()
    self:refresh()
end

function DepotDialog:onTabSell()
    self.tab = DepotDialog.TAB_SELL
    self.pageIndex = 0
    self:_syncTabSections()
    self:refresh()
end

function DepotDialog:onTabProducts()
    self.tab = DepotDialog.TAB_PRODUCTS
    self.pageIndex = 0
    self.selectedProduct = nil
    self.productQuantity = 1
    self:_syncTabSections()
    self:refresh()
end

function DepotDialog:onTabOrder()
    self.tab = DepotDialog.TAB_ORDER
    self.pageIndex = 0
    self:_syncTabSections()
    self:refresh()
end

function DepotDialog:_syncTabSections()
    local isBuy      = (self.tab == DepotDialog.TAB_BUY)
    local isProducts = (self.tab == DepotDialog.TAB_PRODUCTS)
    local isOrder    = (self.tab == DepotDialog.TAB_ORDER)
    if self.preOrderDivider  then self.preOrderDivider:setVisible(isBuy or isProducts or isOrder) end
    if self.preOrderRow      then self.preOrderRow:setVisible(isBuy) end
    if self.productsOrderRow then self.productsOrderRow:setVisible(isProducts) end
    if self.orderPanel       then self.orderPanel:setVisible(isOrder) end
end

-- ─── Refresh ─────────────────────────────────────────────

function DepotDialog:refresh()
    self:updateSeasonLabel()
    if self.tab == DepotDialog.TAB_BUY then
        if self.colTypeHeader  then self.colTypeHeader:setText(tr("fd_col_type",   "Fill Type"))    end
        if self.colStockHeader then self.colStockHeader:setText(tr("fd_col_stock", "Depot Stock"))  end
        if self.colPriceHeader then self.colPriceHeader:setText(tr("fd_col_price", "Price / 1kL")) end
        self:refreshBuyTab()
    elseif self.tab == DepotDialog.TAB_SELL then
        if self.colTypeHeader  then self.colTypeHeader:setText(tr("fd_col_type",    "Fill Type"))   end
        if self.colStockHeader then self.colStockHeader:setText(tr("fd_col_amount", "Amount"))      end
        if self.colPriceHeader then self.colPriceHeader:setText(tr("fd_col_revenue","Revenue"))     end
        self:refreshSellTab()
    elseif self.tab == DepotDialog.TAB_PRODUCTS then
        if self.colTypeHeader  then self.colTypeHeader:setText(tr("fd_col_type",   "Fill Type"))    end
        if self.colStockHeader then self.colStockHeader:setText(tr("fd_col_stock", "Depot Stock"))  end
        if self.colPriceHeader then self.colPriceHeader:setText(tr("fd_col_price", "Price / 1kL")) end
        self:refreshProductsTab()
    else
        if self.colTypeHeader  then self.colTypeHeader:setText(tr("fd_col_type",   "Fill Type"))    end
        if self.colStockHeader then self.colStockHeader:setText(tr("fd_col_stock", "In Stock"))     end
        if self.colPriceHeader then self.colPriceHeader:setText(tr("fd_col_needed","Needed"))       end
        self:refreshOrderTab()
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
        -- Single vehicle scan across all fill types (avoids N separate 96-vehicle searches)
        local nearbyFills = system:buildNearbyFillMap(self.depotId)
        for _, ft in ipairs(self.fillTypes) do
            if ft.fillTypeIndex and ft.fillTypeIndex > 0 then
                local entry = nearbyFills[ft.fillTypeIndex]
                if entry then
                    local rev = pricing and pricing:calculateSellRevenue(ft.name, entry.fillLevel) or 0
                    table.insert(sellTypes, {ft = ft, liters = entry.fillLevel, revenue = rev})
                end
            end
        end
    end

    -- Cache so executeSell uses the same snapshot as what was displayed
    self.sellList = sellTypes

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

function DepotDialog:refreshProductsTab()
    local system  = g_DepotManager and g_DepotManager.depotSystem
    local pricing = g_DepotManager and g_DepotManager.pricing

    if self.statusText then
        if #self.productFillTypes == 0 then
            self.statusText:setText(tr("fd_products_none", "No physical products available."))
        else
            self.statusText:setText("")
        end
    end

    for slot = 1, DepotDialog.ROWS do
        local ftIdx = self.pageIndex + slot
        local row   = self.rows[slot]
        local ft    = self.productFillTypes[ftIdx]

        if ft and row then
            local stored      = system and system:getStorageLevel(self.depotId, ft.name) or 0
            local pricePerUnit = pricing and
                (pricing:getBuyPrice(ft.name) * ft.litresPerUnit) or 0
            local priceStr = string.format("$%.2f/unit", pricePerUnit)
            local stockStr
            if stored <= 0 then
                stockStr = tr("fd_depot_stock_stocking", "Stocking")
            else
                local units = math.floor(stored / ft.litresPerUnit)
                stockStr = string.format("%d units", units)
            end

            if row.nameEl  then row.nameEl:setText(ft.displayName or ft.name) end
            if row.stockEl then row.stockEl:setText(stockStr) end
            if row.priceEl then row.priceEl:setText(priceStr) end

            local isSelected = self.selectedProduct and self.selectedProduct.name == ft.name
            if row.actionTxt then
                if isSelected then
                    row.actionTxt:setText(tr("fd_depot_selected", "Selected"))
                elseif ft.productLabel == "bag" then
                    row.actionTxt:setText(tr("fd_products_order_bag", "Order Bag"))
                else
                    row.actionTxt:setText(tr("fd_products_order_tank", "Order Tank"))
                end
            end
            if row.actionBtn then row.actionBtn:setVisible(true) end
        else
            self:clearRow(slot)
        end
    end

    self:_updateProductsOrderRow()
end

function DepotDialog:_updateProductsOrderRow()
    local pricing = g_DepotManager and g_DepotManager.pricing
    local ft = self.selectedProduct

    if self.prodSelectedName then
        self.prodSelectedName:setText(ft and (ft.displayName or ft.name) or "—")
    end
    if self.prodQtyDisplay then
        self.prodQtyDisplay:setText(string.format("×%d", self.productQuantity))
    end
    if self.prodTotalPrice then
        if ft and pricing then
            local total = pricing:getBuyPrice(ft.name) * ft.litresPerUnit * self.productQuantity
            self.prodTotalPrice:setText(string.format("$%.2f", total))
        else
            self.prodTotalPrice:setText("")
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
    local total
    if self.tab == DepotDialog.TAB_BUY then
        total = #self.fillTypes
    elseif self.tab == DepotDialog.TAB_SELL then
        total = #self.sellList
    elseif self.tab == DepotDialog.TAB_PRODUCTS then
        total = #self.productFillTypes
    else
        -- ORDER tab: count items that would be ordered
        local ds = g_DepotManager and g_DepotManager.deliverySystem
        local order = ds and ds:calculateOrder(self.depotId)
        total = (order and #order.items) or 0
    end

    local maxPage = math.max(0, math.ceil(total / DepotDialog.ROWS) - 1)
    local curPage = math.floor(self.pageIndex / DepotDialog.ROWS)

    if self.pageLabel then
        self.pageLabel:setText(string.format("%d / %d", curPage + 1, maxPage + 1))
    end
    if self.prevPageBtn then self.prevPageBtn:setVisible(self.pageIndex > 0) end
    if self.nextPageBtn then self.nextPageBtn:setVisible(self.pageIndex + DepotDialog.ROWS < total) end
end

function DepotDialog:getSellCount()
    return #self.sellList
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
    local ft     = self.selectedFillType
    local system = g_DepotManager and g_DepotManager.depotSystem

    -- If a compatible vehicle is already parked near the depot, fill it directly
    local vehicle, unitIndex = system and system:findCompatibleVehicle(
        self.depotId, ft.fillTypeIndex, false)

    if vehicle and unitIndex then
        DepotPurchaseEvent.sendToServer(
            self.depotId, ft.name, ft.fillTypeIndex, self.orderAmount, farmId)
        self:showStatus(string.format(
            tr("fd_depot_filling", "Filling %.0fL of %s into your vehicle..."),
            self.orderAmount, ft.displayName or ft.name))
    else
        -- No vehicle nearby — set pending order for silo collection
        if g_DepotManager then
            g_DepotManager:setPendingOrder(
                farmId, self.depotId,
                ft.name, ft.fillTypeIndex,
                self.orderAmount,
                ft.displayName or ft.name)
        end
        self:showStatus(string.format(
            tr("fd_depot_order_set", "Order set: %s %.0fL — walk to silo to collect."),
            ft.displayName or ft.name, self.orderAmount))
    end
end

-- ─── Row Action (Select for Buy/Products, Sell All for Sell) ──────

function DepotDialog:onRowAction(rowSlot)
    if self.tab == DepotDialog.TAB_SELL then
        self:executeSell(rowSlot)
    elseif self.tab == DepotDialog.TAB_PRODUCTS then
        self:selectProductRow(rowSlot)
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

function DepotDialog:selectProductRow(rowSlot)
    local ftIdx = self.pageIndex + rowSlot
    local ft    = self.productFillTypes[ftIdx]
    if not ft then return end
    self.selectedProduct = ft
    self.productQuantity = 1
    self:showStatus("")
    self:refreshProductsTab()
end

function DepotDialog:onProductQtyMinus()
    self.productQuantity = math.max(1, self.productQuantity - 1)
    self:_updateProductsOrderRow()
end

function DepotDialog:onProductQtyPlus()
    self.productQuantity = math.min(DepotConstants.MAX_PRODUCT_QUANTITY, self.productQuantity + 1)
    self:_updateProductsOrderRow()
end

function DepotDialog:onProductConfirm()
    if not self.selectedProduct then
        self:showStatus(tr("fd_depot_select_first", "Select a fill type first."))
        return
    end

    local farmId = g_localPlayer and g_localPlayer.farmId or 1
    local ft     = self.selectedProduct
    local system = g_DepotManager and g_DepotManager.depotSystem

    local stored = system and system:getStorageLevel(self.depotId, ft.name) or 0
    local litresNeeded = self.productQuantity * ft.litresPerUnit
    if stored < litresNeeded then
        self:showStatus(tr("fd_products_no_stock", "Insufficient depot stock for this order."))
        return
    end

    DepotProductOrderEvent.sendToServer(
        self.depotId, ft.name, ft.fillTypeIndex, self.productQuantity, farmId)

    local label = ft.productLabel == "bag"
        and tr("fd_products_label_bag", "Bag(s)")
        or  tr("fd_products_label_tank", "Tank(s)")
    self:showStatus(string.format(
        tr("fd_products_ordered", "%d× %s %s ordered — delivering to depot."),
        self.productQuantity, ft.displayName or ft.name, label))
end

function DepotDialog:executeSell(rowSlot)
    local entry = self.sellList[self.pageIndex + rowSlot]
    if not entry then return end
    local farmId = g_localPlayer and g_localPlayer.farmId or 1
    self:showStatus(string.format(
        tr("fd_depot_filling", "Selling %.0fL %s..."),
        entry.liters, entry.ft.displayName or entry.ft.name))
    DepotSellEvent.sendToServer(
        self.depotId, entry.ft.name, entry.ft.fillTypeIndex, entry.liters, farmId)
end

-- ─── ORDER Tab ───────────────────────────────────────────

function DepotDialog:refreshOrderTab()
    local ds       = g_DepotManager and g_DepotManager.deliverySystem
    local delivery = ds and ds:getDelivery(self.depotId)

    -- When a delivery is active, show its items with live stock readings.
    -- Otherwise show a fresh calculation of what would be ordered.
    local order = ds and ds:calculateOrder(self.depotId)
    local items
    if delivery then
        -- Refresh stored values from live depot data so column 2 is current
        local system = g_DepotManager and g_DepotManager.depotSystem
        for _, item in ipairs(delivery.items) do
            item.stored = (system and system:getStorageLevel(self.depotId, item.fillTypeName)) or 0
        end
        items = delivery.items
    else
        items = (order and order.items) or {}
    end

    for slot = 1, DepotDialog.ROWS do
        local ftIdx = self.pageIndex + slot
        local row   = self.rows[slot]
        local item  = items[ftIdx]

        if item and row then
            local stockStr  = string.format("%dL", math.floor(item.stored or 0))
            local neededStr = string.format("%dL", math.floor(item.needed or 0))
            if row.nameEl  then row.nameEl:setText(item.displayName or item.fillTypeName) end
            if row.stockEl then row.stockEl:setText(stockStr) end
            if row.priceEl then row.priceEl:setText(neededStr) end
            if row.actionBtn then row.actionBtn:setVisible(false) end
        else
            self:clearRow(slot)
        end
    end

    self:_updateOrderPanel(delivery, order)
end

function DepotDialog:_updateOrderPanel(delivery, order)
    local ds = g_DepotManager and g_DepotManager.deliverySystem

    if delivery then
        local status = delivery.status
        if status == DeliverySystem.STATUS.PENDING then
            local penalty    = delivery.deliveryCost * DepotConstants.DELIVERY.CANCEL_PENALTY
            local penaltyStr = string.format("$%.2f", penalty)
            local costStr    = string.format(
                tr("fd_delivery_status_pending", "Delivery pending — drive to Pickup Zone to collect  |  Cancel penalty: %s"),
                penaltyStr)
            if self.orderCostText then self.orderCostText:setText(costStr) end
            if self.orderActionTxt then
                self.orderActionTxt:setText(tr("fd_delivery_cancel_btn", "Cancel Order"))
            end
            if self.orderActionBtn then self.orderActionBtn:setVisible(true) end

        elseif status == DeliverySystem.STATUS.LOADED then
            local canComplete = ds and ds:isDeliveryTruckNearDepot(self.depotId)
            local dist        = ds and ds:getDeliveryTruckDistance(self.depotId)
            local msg
            if canComplete then
                msg = tr("fd_delivery_status_ready", "Delivery ready — click to stock your depot.")
            elseif dist then
                msg = string.format(
                    tr("fd_delivery_status_park", "Park delivery vehicle within 25m of unload zone  (%.0fm away)"),
                    dist)
            else
                msg = tr("fd_delivery_status_return", "Return to depot and park near the unload zone.")
            end
            if self.orderCostText then self.orderCostText:setText(msg) end
            if self.orderActionTxt then
                self.orderActionTxt:setText(tr("fd_delivery_complete_btn", "Complete Delivery"))
            end
            if self.orderActionBtn then self.orderActionBtn:setVisible(true) end
        end

    else
        -- No active delivery
        if not ds or not next(g_DepotManager.pickupNodes or {}) then
            if self.orderCostText then
                self.orderCostText:setText(
                    tr("fd_delivery_no_pickup_placed",
                       "Place a Fertilizer Supplier pickup zone near the in-game shop first."))
            end
            if self.orderActionBtn then self.orderActionBtn:setVisible(false) end
        elseif not order or #order.items == 0 then
            if self.orderCostText then
                self.orderCostText:setText(
                    tr("fd_delivery_all_full", "All fill types are at capacity — no delivery needed."))
            end
            if self.orderActionBtn then self.orderActionBtn:setVisible(false) end
        else
            local costStr = string.format(
                tr("fd_delivery_cost_summary", "Base: $%.2f  +  Fee: $%.2f  =  Total: $%.2f"),
                order.baseCost, order.fee, order.deliveryCost)
            if self.orderCostText then self.orderCostText:setText(costStr) end
            if self.orderActionTxt then
                self.orderActionTxt:setText(tr("fd_delivery_place_btn", "Place Delivery Order"))
            end
            if self.orderActionBtn then self.orderActionBtn:setVisible(true) end
        end
    end
end

-- Single action button callback — dispatches based on current delivery state.
function DepotDialog:onOrderAction()
    local ds     = g_DepotManager and g_DepotManager.deliverySystem
    if not ds then return end
    local delivery = ds:getDelivery(self.depotId)
    local farmId   = g_localPlayer and g_localPlayer.farmId or 1

    if not delivery then
        -- Place new delivery order
        local errKey = ds:canPlaceOrder(self.depotId, farmId)
        if errKey then
            self:showStatus(tr(errKey, errKey))
            return
        end
        local order     = ds:calculateOrder(self.depotId)
        local costStr   = string.format("$%.2f", order.deliveryCost)
        local itemCount = #order.items
        local text = string.format(
            tr("fd_delivery_order_confirm",
               "Place delivery order for %d fill type(s)?\n\nTotal cost on pickup: %s\n(10%% delivery fee included)"),
            itemCount, costStr)
        YesNoDialog.show(function(yes)
            if not yes then return end
            DepotDeliveryOrderEvent.sendToServer(self.depotId, farmId)
            self:showStatus(tr("fd_delivery_order_placed", "Order placed — drive to the Pickup Zone."))
        end, nil, text)

    elseif delivery.status == DeliverySystem.STATUS.PENDING then
        -- Cancel with penalty warning
        local penalty  = delivery.deliveryCost * DepotConstants.DELIVERY.CANCEL_PENALTY
        local penaltyStr = string.format("$%.2f", penalty)
        local text = string.format(
            tr("fd_delivery_cancel_confirm",
               "Cancel delivery order?\n\nA penalty of %s (20%% of delivery cost) will be deducted."),
            penaltyStr)
        YesNoDialog.show(function(yes)
            if not yes then return end
            DepotDeliveryCancelEvent.sendToServer(self.depotId, farmId)
            self:showStatus(tr("fd_delivery_cancelled", "Delivery cancelled."))
        end, nil, text)

    elseif delivery.status == DeliverySystem.STATUS.LOADED then
        -- Complete delivery
        local text = tr("fd_delivery_complete_confirm",
            "Complete delivery and stock your depot?\n\nAll ordered fill types will be added to storage.")
        YesNoDialog.show(function(yes)
            if not yes then return end
            DepotDeliveryCompleteEvent.sendToServer(self.depotId, farmId)
            self:showStatus(tr("fd_delivery_completing", "Delivery complete! Stock has been added."))
        end, nil, text)
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
    local total
    if self.tab == DepotDialog.TAB_BUY then
        total = #self.fillTypes
    elseif self.tab == DepotDialog.TAB_SELL then
        total = #self.sellList
    elseif self.tab == DepotDialog.TAB_PRODUCTS then
        total = #self.productFillTypes
    else
        local ds = g_DepotManager and g_DepotManager.deliverySystem
        local order = ds and ds:calculateOrder(self.depotId)
        total = (order and #order.items) or 0
    end
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
