local Blitbuffer   = require("ffi/blitbuffer")
local Device       = require("device")
local Font         = require("ui/font")
local Geom         = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText   = require("ui/rendertext")
local Size         = require("ui/size")

local gwb      = require("grid_widget_base")
local drawLine = gwb.drawLine

local MinesweeperBoard = require("board")

local STATE_HIDDEN   = MinesweeperBoard.STATE_HIDDEN
local STATE_REVEALED = MinesweeperBoard.STATE_REVEALED
local STATE_FLAGGED  = MinesweeperBoard.STATE_FLAGGED

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------

local C_BG          = Blitbuffer.COLOR_WHITE
local C_HIDDEN      = Blitbuffer.COLOR_GRAY_E
local C_REVEALED    = Blitbuffer.COLOR_WHITE
local C_SELECTED    = Blitbuffer.COLOR_GRAY_D
local C_MINE_BG     = Blitbuffer.COLOR_GRAY_3
local C_FLAG_FG     = Blitbuffer.COLOR_BLACK
local C_BORDER      = Blitbuffer.COLOR_BLACK
local C_GRID        = Blitbuffer.COLOR_GRAY_9

-- Digit colours by count (1-8): use grey shades
local DIGIT_COLORS = {
    Blitbuffer.COLOR_BLACK,    -- 1
    Blitbuffer.COLOR_GRAY_4,   -- 2
    Blitbuffer.COLOR_GRAY_4,   -- 3
    Blitbuffer.COLOR_GRAY_2,   -- 4
    Blitbuffer.COLOR_GRAY_2,   -- 5
    Blitbuffer.COLOR_BLACK,    -- 6
    Blitbuffer.COLOR_BLACK,    -- 7
    Blitbuffer.COLOR_BLACK,    -- 8
}

-- ---------------------------------------------------------------------------
-- MinesweeperBoardWidget
-- ---------------------------------------------------------------------------

local MinesweeperBoardWidget = InputContainer:extend{
    board        = nil,
    cellTapCallback  = nil,
    cellHoldCallback = nil,
    max_width    = 0,
    max_height   = 0,
}

function MinesweeperBoardWidget:init()
    local board = self.board
    local rows, cols = board.rows, board.cols

    -- Fit board into available space, keeping cells square
    local cell = math.floor(math.min(self.max_width / cols, self.max_height / rows))
    cell = math.max(cell, 10)
    self.cell   = cell
    self.w      = cell * cols
    self.h      = cell * rows

    self.dimen  = Geom:new{ w = self.w, h = self.h }

    local face_sz = math.max(6, math.floor(cell * 0.55))
    self.number_face = Font:getFace("smallinfofont", face_sz)

    local flag_sz = math.max(5, math.floor(cell * 0.45))
    self.flag_face = Font:getFace("smallinfofont", flag_sz)

    self.paint_rect = nil

    self:_registerGestures()
end

function MinesweeperBoardWidget:_registerGestures()
    self.ges_events = {
        CellTap  = { GestureRange:new{ ges = "tap",          range = self.dimen } },
        CellHold = { GestureRange:new{ ges = "hold_release", range = self.dimen } },
    }
end

function MinesweeperBoardWidget:onCellTap(ges)
    if not self.paint_rect then return end
    local r, c = self:_cellAt(ges.pos.x, ges.pos.y)
    if r and self.cellTapCallback then self.cellTapCallback(r, c) end
    return true
end

function MinesweeperBoardWidget:onCellHold(ges)
    if not self.paint_rect then return end
    local r, c = self:_cellAt(ges.pos.x, ges.pos.y)
    if r and self.cellHoldCallback then self.cellHoldCallback(r, c) end
    return true
end

function MinesweeperBoardWidget:_cellAt(px, py)
    local rect = self.paint_rect
    if not rect then return nil end
    local lx = px - rect.x
    local ly = py - rect.y
    if lx < 0 or ly < 0 or lx >= self.w or ly >= self.h then return nil end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    local board = self.board
    if r < 1 or r > board.rows or c < 1 or c > board.cols then return nil end
    return r, c
end

function MinesweeperBoardWidget:refresh()
    local UIManager = require("ui/uimanager")
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function MinesweeperBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local rows, cols = board.rows, board.cols
    local cell = self.cell
    local thin = Size.line.thin or 1

    -- Background
    bb:paintRect(x, y, self.w, self.h, C_BG)

    -- Cell backgrounds
    for r = 1, rows do
        for c = 1, cols do
            local cx = x + (c - 1) * cell
            local cy = y + (r - 1) * cell
            local st = board.state[r][c]
            local bg
            if st == STATE_HIDDEN then
                bg = C_HIDDEN
            elseif st == STATE_REVEALED and board.mines[r][c] then
                bg = C_MINE_BG
            else
                bg = C_REVEALED
            end
            bb:paintRect(cx, cy, cell, cell, bg)
        end
    end

    -- Grid lines
    for i = 0, cols do
        drawLine(bb, x + i * cell, y, thin, self.h, C_GRID)
    end
    for i = 0, rows do
        drawLine(bb, x, y + i * cell, self.w, thin, C_GRID)
    end

    -- Outer border (thick)
    local thick = math.max(2, math.floor(cell * 0.06))
    drawLine(bb, x,              y,              self.w, thick, C_BORDER)
    drawLine(bb, x,              y + self.h - thick, self.w, thick, C_BORDER)
    drawLine(bb, x,              y,              thick, self.h, C_BORDER)
    drawLine(bb, x + self.w - thick, y,          thick, self.h, C_BORDER)

    -- Cell content
    local pad = math.max(1, math.floor(cell * 0.1))
    local cinn = cell - 2 * pad

    for r = 1, rows do
        for c = 1, cols do
            local cx = x + (c - 1) * cell
            local cy = y + (r - 1) * cell
            local st = board.state[r][c]

            if st == STATE_REVEALED then
                if board.mines[r][c] then
                    -- Mine symbol: filled circle
                    local radius = math.floor(cell * 0.28)
                    local mx = cx + math.floor(cell / 2)
                    local my = cy + math.floor(cell / 2)
                    bb:paintCircle(mx, my, radius, C_FLAG_FG)
                else
                    local cnt = board.counts[r][c]
                    if cnt > 0 then
                        local text  = tostring(cnt)
                        local color = DIGIT_COLORS[cnt] or Blitbuffer.COLOR_BLACK
                        local m     = RenderText:sizeUtf8Text(0, cinn, self.number_face, text, true, false)
                        local base  = cy + pad + math.floor((cinn + m.y_top - m.y_bottom) / 2)
                        local tx    = cx + pad + math.floor((cinn - m.x) / 2)
                        RenderText:renderUtf8Text(bb, tx, base, self.number_face, text, true, false, color)
                    end
                end
            elseif st == STATE_FLAGGED then
                -- Flag: "F" text
                local text  = "F"
                local color = C_FLAG_FG
                local m     = RenderText:sizeUtf8Text(0, cinn, self.flag_face, text, true, false)
                local base  = cy + pad + math.floor((cinn + m.y_top - m.y_bottom) / 2)
                local tx    = cx + pad + math.floor((cinn - m.x) / 2)
                RenderText:renderUtf8Text(bb, tx, base, self.flag_face, text, true, false, color)
            end
        end
    end
end

return MinesweeperBoardWidget
