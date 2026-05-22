-- =========================================================
-- FS25 Fertilizer Depot - Delivery Status HUD
-- =========================================================
-- Shows active delivery status as a movable/scalable panel.
-- RMB on panel → enter edit mode (drag / corner-resize).
-- RMB again → exit edit mode and save position.
-- Position + scale persisted per-savegame to
--   <savegameDir>/FS25_FertilizerDepot_hud.xml
-- =========================================================

local _hudModName = g_currentModName

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[_hudModName]
    local i18n   = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and not text:find("^Missing '") then
            return text
        end
    end
    return fallback or key
end

---@class DepotHUD
DepotHUD = {}
local DepotHUD_mt = Class(DepotHUD)

DepotHUD.MIN_SCALE     = 0.60
DepotHUD.MAX_SCALE     = 2.00
DepotHUD.RESIZE_HANDLE = 0.008

-- =========================================================
-- Constructor
-- =========================================================

function DepotHUD.new()
    local self = setmetatable({}, DepotHUD_mt)

    -- Default anchor: top-left area
    self.posX       = 0.01
    self.posY       = 0.92
    self.scale      = 1.0
    self.panelWidth = 0.20   -- normalized width at scale 1.0

    -- Layout constants at scale 1.0
    self.PAD       = 0.007
    self.LINE_H    = 0.019
    self.TEXT_HEAD = 0.013
    self.TEXT_BODY = 0.012
    self.TEXT_HINT = 0.0095

    -- Edit / drag state
    self.editMode    = false
    self.dragging    = false
    self.resizing    = false
    self.dragOffX    = 0
    self.dragOffY    = 0
    self.resStartX   = 0
    self.resStartY   = 0
    self.resStartSc  = 1.0
    self.hoverCorner = nil
    self.animTimer   = 0

    -- Cached panel bounds (for hit-testing)
    self.lastBgX = 0
    self.lastBgY = 0
    self.lastBgW = 0
    self.lastBgH = 0

    -- Layout is loaded lazily on first draw (savegame dir not ready at construction)
    self.layoutLoaded = false

    -- 1×1 pixel overlay for filled rectangles
    self.bgOverlay = nil
    if createImageOverlay then
        self.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    self.COLORS = {
        BG          = {0.05, 0.05, 0.05, 0.82},
        BORDER      = {0.20, 0.20, 0.20, 0.45},
        SHADOW      = {0.00, 0.00, 0.00, 0.35},
        DIVIDER     = {0.25, 0.25, 0.25, 0.85},
        HEADER      = {1.00, 1.00, 1.00, 1.00},
        PENDING     = {0.95, 0.80, 0.20, 1.00},
        LOADED      = {0.30, 0.90, 0.30, 1.00},
        HINT        = {0.52, 0.52, 0.52, 0.75},
        EDIT_BORDER = {1.00, 0.60, 0.10, 0.90},
        EDIT_HANDLE = {1.00, 0.70, 0.20, 0.85},
    }

    return self
end

-- =========================================================
-- Cleanup
-- =========================================================

function DepotHUD:delete()
    if self.editMode then self:exitEditMode() end
    if self.bgOverlay then
        delete(self.bgOverlay)
        self.bgOverlay = nil
    end
end

-- =========================================================
-- Persistence
-- =========================================================

function DepotHUD:_getLayoutPath()
    if g_currentMission and g_currentMission.missionInfo
    and g_currentMission.missionInfo.savegameDirectory then
        return g_currentMission.missionInfo.savegameDirectory
               .. "/FS25_FertilizerDepot_hud.xml"
    end
end

function DepotHUD:saveLayout()
    local path = self:_getLayoutPath()
    if not path then return end
    local xml = XMLFile.create("fdHud", path, "hudLayout")
    if xml then
        xml:setFloat("hudLayout.posX",  self.posX)
        xml:setFloat("hudLayout.posY",  self.posY)
        xml:setFloat("hudLayout.scale", self.scale)
        xml:save()
        xml:delete()
    end
end

function DepotHUD:loadLayout()
    local path = self:_getLayoutPath()
    if not path or not fileExists(path) then return end
    local xml = XMLFile.load("fdHud", path)
    if xml then
        self.posX  = xml:getFloat("hudLayout.posX",  self.posX)
        self.posY  = xml:getFloat("hudLayout.posY",  self.posY)
        self.scale = xml:getFloat("hudLayout.scale", self.scale)
        xml:delete()
    end
end

-- =========================================================
-- Edit mode
-- =========================================================

function DepotHUD:enterEditMode()
    self.editMode = true
    self.dragging = false
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true)
    end
end

function DepotHUD:exitEditMode()
    self.editMode    = false
    self.dragging    = false
    self.resizing    = false
    self.hoverCorner = nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    self:saveLayout()
end

-- =========================================================
-- Geometry helpers
-- =========================================================

function DepotHUD:isPointerOverHUD(px, py)
    return px >= self.lastBgX and px <= self.lastBgX + self.lastBgW
       and py >= self.lastBgY and py <= self.lastBgY + self.lastBgH
end

function DepotHUD:_handleRects()
    local hs = DepotHUD.RESIZE_HANDLE
    local bx, by, bw, bh = self.lastBgX, self.lastBgY, self.lastBgW, self.lastBgH
    return {
        bl = {x = bx,            y = by,            w = hs, h = hs},
        br = {x = bx + bw - hs,  y = by,            w = hs, h = hs},
        tl = {x = bx,            y = by + bh - hs,  w = hs, h = hs},
        tr = {x = bx + bw - hs,  y = by + bh - hs,  w = hs, h = hs},
    }
end

function DepotHUD:_hitCorner(px, py)
    for k, r in pairs(self:_handleRects()) do
        if px >= r.x and px <= r.x + r.w
        and py >= r.y and py <= r.y + r.h then
            return k
        end
    end
end

function DepotHUD:_clamp()
    local bw = self.lastBgW
    local bh = self.lastBgH
    self.posX = math.max(0.01, math.min(1.0 - bw - 0.01, self.posX))
    self.posY = math.max(bh + 0.01, math.min(0.98, self.posY))
end

-- =========================================================
-- Mouse event (called from FSBaseMission.mouseEvent hook)
-- =========================================================

function DepotHUD:onMouseEvent(posX, posY, isDown, isUp, button)
    -- RMB: toggle edit mode
    if isDown and button == 3 then
        if self.editMode then self:exitEditMode() else self:enterEditMode() end
        return
    end

    if not self.editMode then return end

    if isDown and button == 1 then
        local corner = self:_hitCorner(posX, posY)
        if corner then
            self.resizing   = true
            self.dragging   = false
            self.resStartX  = posX
            self.resStartY  = posY
            self.resStartSc = self.scale
        elseif self:isPointerOverHUD(posX, posY) then
            self.dragging  = true
            self.resizing  = false
            self.dragOffX  = posX - self.posX
            self.dragOffY  = posY - self.posY
        end
        return
    end

    if isUp and button == 1 then
        if self.dragging or self.resizing then
            self.dragging = false
            self.resizing = false
            self:_clamp()
        end
        return
    end

    -- Mouse movement
    if self.dragging then
        self.posX = math.max(0.0, math.min(1.0 - self.lastBgW, posX - self.dragOffX))
        self.posY = math.max(0.05, math.min(0.98, posY - self.dragOffY))
    end

    if self.resizing then
        local cx = self.lastBgX + self.lastBgW * 0.5
        local cy = self.lastBgY + self.lastBgH * 0.5
        local sd = math.sqrt((self.resStartX - cx)^2 + (self.resStartY - cy)^2)
        local cd = math.sqrt((posX - cx)^2          + (posY - cy)^2)
        local delta = (cd - sd) * 2.5
        self.scale = math.max(DepotHUD.MIN_SCALE,
            math.min(DepotHUD.MAX_SCALE, self.resStartSc + delta))
        self:_clamp()
    end

    if not self.dragging and not self.resizing then
        self.hoverCorner = self:_hitCorner(posX, posY)
    end
end

-- =========================================================
-- Update (called every frame from DepotManager:update)
-- =========================================================

function DepotHUD:update(dt)
    self.animTimer = self.animTimer + dt
    if self.editMode then
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true)
        end
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            self:exitEditMode()
        end
        if not self.dragging and not self.resizing and g_inputBinding then
            self.hoverCorner = self:_hitCorner(
                g_inputBinding.mousePosXLast or 0,
                g_inputBinding.mousePosYLast or 0)
        end
    else
        self.hoverCorner = nil
    end
end

-- =========================================================
-- Draw (called from FSBaseMission.draw hook)
-- =========================================================

function DepotHUD:draw()
    if not g_currentMission or not g_currentMission:getIsClient() then return end
    if not self.bgOverlay then return end

    -- Deferred layout load — savegame dir is not ready at construction time
    if not self.layoutLoaded then
        self.layoutLoaded = true
        self:loadLayout()
    end

    if not self.editMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then return end
        if g_currentMission.hud and g_currentMission.hud.ingameMap then
            if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then return end
        end
    end

    local ds = g_DepotManager and g_DepotManager.deliverySystem
    if not ds then return end

    local farmId = g_localPlayer and g_localPlayer.farmId or 0
    local status, costStr = nil, nil
    for _, rec in pairs(ds.deliveries) do
        if rec.farmId == farmId then
            status  = rec.status
            costStr = g_i18n and g_i18n:formatMoney(rec.deliveryCost, 0, true)
                      or string.format("$%.0f", rec.deliveryCost)
            break
        end
    end

    if not status or status == DeliverySystem.STATUS.NONE then
        -- In edit mode show a placeholder so the panel is visible for positioning
        if self.editMode then
            self:_drawPanel(DeliverySystem.STATUS.PENDING, "$0")
        end
        return
    end

    self:_drawPanel(status, costStr)
end

-- =========================================================
-- Panel rendering
-- =========================================================

function DepotHUD:_drawPanel(status, costStr)
    local sc  = self.scale
    local x   = self.posX
    local w   = self.panelWidth * sc
    local pad = self.PAD  * sc
    local lh  = self.LINE_H * sc

    -- 3 content rows: header, status, hint
    local bgH = pad * 2 + 3 * lh + 0.004 * sc
    local bgX = x - pad
    local bgY = self.posY - bgH + pad
    local bgW = w + pad * 2

    self.lastBgX = bgX
    self.lastBgY = bgY
    self.lastBgW = bgW
    self.lastBgH = bgH

    -- Drop shadow
    self:_rect(bgX + 0.002, bgY - 0.002, bgW, bgH, self.COLORS.SHADOW)
    -- Background
    self:_rect(bgX, bgY, bgW, bgH, self.COLORS.BG)
    -- Border
    local bw = 0.0012
    self:_rect(bgX,            bgY + bgH - bw, bgW, bw, self.COLORS.BORDER)
    self:_rect(bgX,            bgY,            bgW, bw, self.COLORS.BORDER)
    self:_rect(bgX,            bgY,            bw, bgH, self.COLORS.BORDER)
    self:_rect(bgX + bgW - bw, bgY,            bw, bgH, self.COLORS.BORDER)

    -- Edit mode chrome
    if self.editMode then
        local pulse = 0.55 + 0.45 * math.sin(self.animTimer * 0.004)
        local ebw   = 0.002
        local ec    = self.COLORS.EDIT_BORDER
        self:_rectA(bgX,             bgY,              bgW, ebw, ec, pulse)
        self:_rectA(bgX,             bgY + bgH - ebw,  bgW, ebw, ec, pulse)
        self:_rectA(bgX,             bgY,              ebw, bgH, ec, pulse)
        self:_rectA(bgX + bgW - ebw, bgY,              ebw, bgH, ec, pulse)
        for k, r in pairs(self:_handleRects()) do
            local isHov = (self.hoverCorner == k)
            self:_rectA(r.x, r.y, r.w, r.h, self.COLORS.EDIT_HANDLE, isHov and 1.0 or 0.65)
        end
    end

    -- ── Content ──────────────────────────────────────────
    local tsHead = self.TEXT_HEAD * sc
    local tsBody = self.TEXT_BODY * sc
    local tsHint = self.TEXT_HINT * sc
    local cy = self.posY - pad

    -- Header
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.HEADER[1], self.COLORS.HEADER[2], self.COLORS.HEADER[3], 1)
    renderText(x, cy - tsHead, tsHead, tr("fd_delivery_hud_header", "Fertilizer Delivery"))
    setTextBold(false)
    cy = cy - lh

    -- Divider
    self:_rect(bgX, cy + lh * 0.35, bgW, 0.001 * sc, self.COLORS.DIVIDER)
    cy = cy - 0.004 * sc

    -- Status line
    local bodyText, statusColor
    if status == DeliverySystem.STATUS.PENDING then
        bodyText    = tr("fd_delivery_hud_pending", "Drive to the pickup zone to collect your order")
        statusColor = self.COLORS.PENDING
    else
        bodyText    = tr("fd_delivery_hud_loaded",  "Return to your depot to complete the delivery")
        statusColor = self.COLORS.LOADED
    end
    setTextColor(statusColor[1], statusColor[2], statusColor[3], 1)
    renderText(x, cy - tsBody, tsBody, bodyText)
    cy = cy - lh

    -- Hint
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(self.COLORS.HINT[1], self.COLORS.HINT[2], self.COLORS.HINT[3], 1)
    local hintText = self.editMode
        and "LMB: drag  |  corner: resize  |  RMB: done"
        or  "Right-click to move"
    renderText(x + w * 0.5, cy - tsHint, tsHint, hintText)

    -- Reset text state
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- =========================================================
-- Render helpers
-- =========================================================

function DepotHUD:_rect(rx, ry, rw, rh, c)
    setOverlayColor(self.bgOverlay, c[1], c[2], c[3], c[4])
    renderOverlay(self.bgOverlay, rx, ry, rw, rh)
end

function DepotHUD:_rectA(rx, ry, rw, rh, c, alpha)
    setOverlayColor(self.bgOverlay, c[1], c[2], c[3], alpha)
    renderOverlay(self.bgOverlay, rx, ry, rw, rh)
end
