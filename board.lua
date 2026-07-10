local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local grid_utils = lrequire("common/grid_utils")
local Timer      = lrequire("common/timer")

local emptyGrid     = grid_utils.emptyGrid
local emptyBoolGrid = grid_utils.emptyBoolGrid
local copyGrid      = grid_utils.copyGrid

-- Cell visible states
local STATE_HIDDEN   = 0
local STATE_REVEALED = 1
local STATE_FLAGGED  = 2

-- Preset configurations: { rows, cols, mines }
local PRESETS = {
    beginner     = { rows =  9, cols =  9, mines = 10 },
    intermediate = { rows = 16, cols = 16, mines = 40 },
    expert       = { rows = 16, cols = 20, mines = 70 },
}
local PRESET_ORDER = { "beginner", "intermediate", "expert" }

-- ---------------------------------------------------------------------------
-- MinesweeperBoard
-- ---------------------------------------------------------------------------

local MinesweeperBoard = {}
MinesweeperBoard.__index = MinesweeperBoard

function MinesweeperBoard:new(opts)
    opts = opts or {}
    local preset = opts.preset or "beginner"
    local cfg    = PRESETS[preset] or PRESETS.beginner
    local obj = setmetatable({
        rows        = cfg.rows,
        cols        = cfg.cols,
        mine_count  = cfg.mines,
        preset      = preset,
        mines       = nil,
        counts      = nil,
        state       = nil,
        started     = false,
        game_over   = false,
        win         = false,
        flags_placed = 0,
        timer       = Timer:new(),
    }, self)
    obj:_reset()
    return obj
end

function MinesweeperBoard:_reset()
    local rows, cols = self.rows, self.cols
    self.mines       = emptyBoolGrid(cols, rows)
    self.counts      = emptyGrid(cols, rows)
    self.state       = emptyGrid(cols, rows)
    self.started     = false
    self.game_over   = false
    self.win         = false
    self.flags_placed = 0
    self.timer:reset()
end

-- Place mines randomly, avoiding (safe_r, safe_c) and its 8-neighbours.
function MinesweeperBoard:_placeMines(safe_r, safe_c)
    local rows, cols = self.rows, self.cols
    local excluded = {}
    for dr = -1, 1 do
        for dc = -1, 1 do
            local nr, nc = safe_r + dr, safe_c + dc
            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols then
                excluded[nr * 1000 + nc] = true
            end
        end
    end

    local candidates = {}
    for r = 1, rows do
        for c = 1, cols do
            if not excluded[r * 1000 + c] then
                candidates[#candidates + 1] = { r, c }
            end
        end
    end

    -- Fisher-Yates partial shuffle
    local placed = 0
    for i = #candidates, math.max(1, #candidates - self.mine_count + 1), -1 do
        local j = math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
        local r, c = candidates[i][1], candidates[i][2]
        self.mines[r][c] = true
        placed = placed + 1
        if placed >= self.mine_count then break end
    end

    -- Compute neighbour counts
    for r = 1, rows do
        for c = 1, cols do
            if not self.mines[r][c] then
                local cnt = 0
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        local nr, nc = r + dr, c + dc
                        if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
                                and self.mines[nr][nc] then
                            cnt = cnt + 1
                        end
                    end
                end
                self.counts[r][c] = cnt
            end
        end
    end
end

-- BFS flood-fill reveal for zero-count cells
function MinesweeperBoard:_floodReveal(r0, c0)
    local rows, cols = self.rows, self.cols
    local queue = { { r0, c0 } }
    local head  = 1
    while head <= #queue do
        local r, c = queue[head][1], queue[head][2]
        head = head + 1
        for dr = -1, 1 do
            for dc = -1, 1 do
                local nr, nc = r + dr, c + dc
                if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
                        and self.state[nr][nc] == STATE_HIDDEN
                        and not self.mines[nr][nc] then
                    self.state[nr][nc] = STATE_REVEALED
                    if self.counts[nr][nc] == 0 then
                        queue[#queue + 1] = { nr, nc }
                    end
                end
            end
        end
    end
end

-- Returns "ok", "mine" (game over), or "already" (no action needed)
function MinesweeperBoard:reveal(r, c)
    if self.game_over or self.win then return "already" end
    if self.state[r][c] ~= STATE_HIDDEN then return "already" end

    if not self.started then
        self:_placeMines(r, c)
        self.started = true
        self.timer:start()
    end

    if self.mines[r][c] then
        self.state[r][c] = STATE_REVEALED
        self.game_over   = true
        self.timer:stop()
        return "mine"
    end

    self.state[r][c] = STATE_REVEALED
    if self.counts[r][c] == 0 then
        self:_floodReveal(r, c)
    end

    if self:_checkWin() then
        self.win = true
        self.timer:stop()
        return "win"
    end
    return "ok"
end

function MinesweeperBoard:toggleFlag(r, c)
    if self.game_over or self.win then return end
    if self.state[r][c] == STATE_REVEALED then return end
    if self.state[r][c] == STATE_HIDDEN then
        self.state[r][c] = STATE_FLAGGED
        self.flags_placed = self.flags_placed + 1
    else
        self.state[r][c] = STATE_HIDDEN
        self.flags_placed = self.flags_placed - 1
    end
end

-- Chord: if a revealed numbered cell has exactly as many adjacent flags as its
-- count, reveal all remaining hidden neighbours.
-- Returns "mine" if a wrong flag caused a detonation, otherwise "ok"/"noop".
function MinesweeperBoard:chord(r, c)
    if self.state[r][c] ~= STATE_REVEALED then return "noop" end
    if self.game_over or self.win then return "noop" end
    local cnt = self.counts[r][c]
    if cnt == 0 then return "noop" end

    local rows, cols = self.rows, self.cols
    local adj_flags = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            local nr, nc = r + dr, c + dc
            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
                    and self.state[nr][nc] == STATE_FLAGGED then
                adj_flags = adj_flags + 1
            end
        end
    end
    if adj_flags ~= cnt then return "noop" end

    local hit_mine = false
    for dr = -1, 1 do
        for dc = -1, 1 do
            local nr, nc = r + dr, c + dc
            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
                    and self.state[nr][nc] == STATE_HIDDEN then
                local res = self:reveal(nr, nc)
                if res == "mine" then hit_mine = true end
            end
        end
    end
    return hit_mine and "mine" or "ok"
end

function MinesweeperBoard:_checkWin()
    local rows, cols = self.rows, self.cols
    for r = 1, rows do
        for c = 1, cols do
            if not self.mines[r][c] and self.state[r][c] ~= STATE_REVEALED then
                return false
            end
        end
    end
    return true
end

function MinesweeperBoard:getRemainingMines()
    return self.mine_count - self.flags_placed
end

-- Reveal all mines (called when game over to show board)
function MinesweeperBoard:revealAllMines()
    local rows, cols = self.rows, self.cols
    for r = 1, rows do
        for c = 1, cols do
            if self.mines[r][c] then
                self.state[r][c] = STATE_REVEALED
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function MinesweeperBoard:serialize()
    local rows, cols = self.rows, self.cols
    local mines_out  = copyGrid(self.mines, cols, rows)
    local counts_out = copyGrid(self.counts, cols, rows)
    local state_out  = copyGrid(self.state, cols, rows)
    return {
        rows         = rows,
        cols         = cols,
        mine_count   = self.mine_count,
        preset       = self.preset,
        mines        = mines_out,
        counts       = counts_out,
        state        = state_out,
        started      = self.started,
        game_over    = self.game_over,
        win          = self.win,
        flags_placed = self.flags_placed,
        timer        = self.timer:serialize(),
    }
end

function MinesweeperBoard:load(data)
    if type(data) ~= "table" or not data.state then return false end
    local rows, cols = data.rows or 9, data.cols or 9
    self.rows        = rows
    self.cols        = cols
    self.mine_count  = data.mine_count or 10
    self.preset      = data.preset or "beginner"
    self.mines       = copyGrid(data.mines  or {}, cols, rows)
    self.counts      = copyGrid(data.counts or {}, cols, rows)
    self.state       = copyGrid(data.state  or {}, cols, rows)
    self.started     = data.started    or false
    self.game_over   = data.game_over  or false
    self.win         = data.win        or false
    self.flags_placed = data.flags_placed or 0
    self.timer = Timer:new()
    if data.timer then self.timer:load(data.timer) end
    return true
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

MinesweeperBoard.STATE_HIDDEN   = STATE_HIDDEN
MinesweeperBoard.STATE_REVEALED = STATE_REVEALED
MinesweeperBoard.STATE_FLAGGED  = STATE_FLAGGED
MinesweeperBoard.PRESETS        = PRESETS
MinesweeperBoard.PRESET_ORDER   = PRESET_ORDER

return MinesweeperBoard
