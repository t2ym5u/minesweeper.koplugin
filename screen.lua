local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase          = require("screen_base")
local MenuHelper          = require("menu_helper")
local MinesweeperBoard    = lrequire("board")
local MinesweeperBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- MinesweeperScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Minesweeper — Rules

Uncover all safe cells without detonating a mine.

Each uncovered cell shows the count of mines among its up-to-8 neighbouring cells.
A cell showing 0 is safe and automatically expands to reveal its neighbours.
Right-tap (or use Flag mode) to flag a suspected mine.
The first tap is always safe — mines are placed after it.

Win by uncovering every non-mine cell.
]])

local GAME_RULES_FR = [[
Démineur — Règles

Découvrez toutes les cases sûres sans faire exploser une mine.

Chaque case découverte affiche le nombre de mines parmi ses 8 cases voisines.
Une case affichant 0 est sûre et révèle automatiquement ses voisines.
Appui long (ou mode Drapeau) pour marquer une mine suspectée.
Le premier appui est toujours sûr — les mines sont placées après.

Gagnez en découvrant toutes les cases sans mine.
]]

local MinesweeperScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MinesweeperScreen:init()
    local state  = self.plugin:loadState()
    self.board   = MinesweeperBoard:new{ preset = self.plugin:getSetting("preset", "beginner") }
    if not self.board:load(state) then
        -- default board already ready from :new
    end
    self.flag_mode = false
    ScreenBase.init(self)
end

function MinesweeperScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function MinesweeperScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local sh           = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    -- Top bar
    local top_button_width = is_landscape
        and math.max(math.floor(sw * 0.38), 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = top_button_width,
        buttons = {{
            { text = _("New"),      callback = function() self:onNewGame() end },
            { id = "preset_button", text = self:getPresetButtonText(),
              callback = function() self:openPresetMenu() end },
            { id = "flag_button",   text = self:getFlagButtonText(),
              callback = function() self:toggleFlagMode() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.preset_button = top_buttons:getButtonById("preset_button")
    self.flag_button   = top_buttons:getButtonById("flag_button")

    -- Board widget
    local margin       = Size.margin.default
    local padding      = Size.padding.large
    local frame_extra  = (padding + margin) * 2

    local board_max_w, board_max_h
    if is_landscape then
        board_max_w = math.floor(sw * 0.55)
        board_max_h = sh - frame_extra - 20
    else
        local top_h    = top_button_width > 0 and 60 or 0
        local bottom_h = 60
        local status_h = 30
        board_max_w = sw - frame_extra
        board_max_h = sh - top_h - bottom_h - status_h - frame_extra * 2 - 40
    end
    board_max_w = math.max(board_max_w, 80)
    board_max_h = math.max(board_max_h, 80)

    self.board_widget = MinesweeperBoardWidget:new{
        board      = self.board,
        max_width  = board_max_w,
        max_height = board_max_h,
        onCellTap  = function(r, c) self:onCellTap(r, c) end,
        onCellHold = function(r, c) self:onCellHold(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    -- Bottom bar
    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = top_button_width,
        buttons = {{
            { text = _("Check"),   callback = function() self:onCheck() end },
        }},
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function MinesweeperScreen:onCellTap(r, c)
    if self.flag_mode then
        self:_doFlag(r, c)
    else
        self:_doReveal(r, c)
    end
end

function MinesweeperScreen:onCellHold(r, c)
    self:_doFlag(r, c)
end

function MinesweeperScreen:_doReveal(r, c)
    local st = self.board.state[r][c]
    local res
    if st == MinesweeperBoard.STATE_REVEALED then
        res = self.board:chord(r, c)
    else
        res = self.board:reveal(r, c)
    end
    if res == "mine" then
        self.board:revealAllMines()
        self.board_widget:refresh()
        self:updateStatus(_("BOOM! Game over."))
    elseif res == "win" then
        self.board_widget:refresh()
        self:updateStatus(_("Congratulations! You cleared the board!"))
    else
        self.board_widget:refresh()
        self:updateStatus()
    end
    self.plugin:saveState(self.board:serialize())
end

function MinesweeperScreen:_doFlag(r, c)
    self.board:toggleFlag(r, c)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function MinesweeperScreen:onNewGame()
    local preset = self.plugin:getSetting("preset", "beginner")
    self.board   = MinesweeperBoard:new{ preset = preset }
    self.flag_mode = false
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function MinesweeperScreen:onCheck()
    if self.board.game_over then
        self:updateStatus(_("Game over."))
    elseif self.board.win then
        self:updateStatus(_("Congratulations! You cleared the board!"))
    else
        local remaining = 0
        local rows, cols = self.board.rows, self.board.cols
        for r = 1, rows do
            for c = 1, cols do
                if not self.board.mines[r][c]
                        and self.board.state[r][c] ~= MinesweeperBoard.STATE_REVEALED then
                    remaining = remaining + 1
                end
            end
        end
        self:updateStatus(T(_("Safe cells remaining: %1"), remaining))
    end
end

function MinesweeperScreen:toggleFlagMode()
    self.flag_mode = not self.flag_mode
    if self.flag_button then
        self.flag_button:setText(self:getFlagButtonText(), self.flag_button.width)
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function MinesweeperScreen:openPresetMenu()
    local presets = {}
    for _, id in ipairs(MinesweeperBoard.PRESET_ORDER) do
        local cfg = MinesweeperBoard.PRESETS[id]
        presets[#presets + 1] = {
            id   = id,
            text = string.format("%s (%d\xC3\x97%d, %d)",
                id:sub(1,1):upper() .. id:sub(2),
                cfg.rows, cfg.cols, cfg.mines),
        }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select preset"),
        sizes     = presets,
        current   = self.plugin:getSetting("preset", "beginner"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("preset", id)
            if self.preset_button then
                self.preset_button:setText(self:getPresetButtonText(), self.preset_button.width)
            end
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function MinesweeperScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.game_over then
        status = _("BOOM! Game over.")
    elseif self.board.win then
        status = _("Congratulations! You cleared the board!")
    else
        local mines_left = self.board:getRemainingMines()
        local time_str   = self.board.timer:format()
        local flag_str   = self.flag_mode and _(" \xC2\xB7 Flag ON") or ""
        status = T(_("Mines: %1 \xC2\xB7 Time: %2%3"), mines_left, time_str, flag_str)
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Button text helpers
-- ---------------------------------------------------------------------------

function MinesweeperScreen:getPresetButtonText()
    local preset = self.plugin:getSetting("preset", "beginner")
    return preset:sub(1,1):upper() .. preset:sub(2)
end

function MinesweeperScreen:getFlagButtonText()
    return self.flag_mode and _("Flag: ON") or _("Flag: OFF")
end

return MinesweeperScreen
