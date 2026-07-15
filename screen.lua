local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
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

    -- Title bar (full width, pinned to top)
    local title_bar = TitleBar:new{
        width                  = sw,
        title                  = _("Minesweeper"),
        left_icon              = "appbar.menu",
        left_icon_tap_callback = function() self:openOptionsMenu() end,
        close_callback         = function() self:closeScreen() end,
        with_bottom_line       = true,
    }
    local tb_h = title_bar:getSize().h

    -- Board sizing
    local margin      = Size.margin.default
    local padding     = Size.padding.large
    local frame_extra = (padding + margin) * 2
    local btn_h       = Size.item.height_default + 2 * Size.padding.buttontable

    local board_max_w, board_max_h
    if is_landscape then
        board_max_w = math.floor(sw * 0.55)
        board_max_h = sh - tb_h - frame_extra - 20
    else
        board_max_w = sw - frame_extra
        board_max_h = sh - tb_h - btn_h - 30 - frame_extra * 2 - 40
    end
    board_max_w = math.max(board_max_w, 80)
    board_max_h = math.max(board_max_h, 80)

    self.board_widget = MinesweeperBoardWidget:new{
        board            = self.board,
        max_width        = board_max_w,
        max_height       = board_max_h,
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
        cellHoldCallback = function(r, c) self:onCellHold(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    -- Footer: game-specific actions
    local btn_w = is_landscape
        and math.max(math.floor(sw * 0.38), 100)
        or  math.floor(sw * 0.9)

    local footer = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_w,
        buttons = {{
            { id = "flag_button", text = self:getFlagButtonText(),
              callback = function() self:toggleFlagMode() end },
            { text = _("Check"), callback = function() self:onCheck() end },
        }},
    }
    self.flag_button = footer:getButtonById("flag_button")

    if is_landscape then
        local avail_h = sh - tb_h
        local right_panel = VerticalGroup:new{
            align = "center",
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            footer,
        }
        local game_row = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
        local game_h   = game_row:getSize().h
        local top_span = math.max(0, math.floor((avail_h - game_h) / 2))
        local bot_span = math.max(0, avail_h - top_span - game_h)
        self.layout = VerticalGroup:new{
            title_bar,
            VerticalSpan:new{ width = top_span },
            game_row,
            VerticalSpan:new{ width = bot_span },
        }
        self[1] = self.layout
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, content, footer)
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Options menu
-- ---------------------------------------------------------------------------

function MinesweeperScreen:openOptionsMenu()
    local dlg
    dlg = ButtonDialog:new{
        title = _("Minesweeper"),
        buttons = {
            {{ text = _("New game"), callback = function()
                UIManager:close(dlg)
                self:onNewGame()
            end }},
            {{ text = T(_("Preset: %1"), self:getPresetButtonText()),
               callback = function()
                UIManager:close(dlg)
                self:openPresetMenu()
            end }},
            {{ text = _("Rules"), callback = function()
                UIManager:close(dlg)
                self:showRules(_.lang() == "fr" and GAME_RULES_FR or GAME_RULES_EN)
            end }},
        },
    }
    UIManager:show(dlg)
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
-- Preset menu
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
