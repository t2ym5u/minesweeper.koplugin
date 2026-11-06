-- ---------------------------------------------------------------------------
-- mine_gen.lua -- no-guess mine layouts.
--
-- MineGen.generate(rows, cols, total, safe_r, safe_c) returns a layout
-- (flat array, index (r-1)*cols+c, true = mine) that a no-trial solver clears
-- entirely from the first tap at (safe_r, safe_c). The tapped cell and its
-- neighbours are always mine-free, so the first tap opens an area.
--
-- The solver only uses what a player sees -- the numbers and the mine
-- counter -- and only direct deductions, never "suppose X, find a
-- contradiction":
--   * one number: no mine left to find => its other hidden neighbours are
--     safe; as many mines left as hidden neighbours => they are all mines;
--   * two nearby numbers: the mines their shared cells can hold are bounded
--     by both; when the bounds meet, the cells only one of them sees are
--     settled (this covers the subset rule and the 1-2-1 patterns);
--   * the mine counter: no mine left => every hidden cell is safe; as many
--     left as hidden cells => all mines; and the same against one number
--     (the mines outside it are the counter minus its own).
--
-- When the solver gets stuck, the layout is changed where it got stuck (the
-- way Simon Tatham's Mines does it): the hidden cells around one number are
-- made all safe, their mines moved to hidden cells no number sees yet, or
-- all mines, taken from such cells. The mine count never changes. Solving
-- goes on from there, and a layout is only accepted once a fresh solve from
-- the first tap clears it. Work is capped by counts, never by the clock, and
-- the only randomness is math.random: a seed always deals the same game.
-- ---------------------------------------------------------------------------

local MineGen = {
    MAX_PERTURB = 400,   -- layout changes per random start
    MAX_STARTS  = 20,    -- random starts before giving up
}

local floor, random = math.floor, math.random

local function buildNeighbours(rows, cols)
    local nb = {}
    for r = 1, rows do
        for c = 1, cols do
            local l = {}
            for dr = -1, 1 do
                for dc = -1, 1 do
                    if dr ~= 0 or dc ~= 0 then
                        local nr, nc = r + dr, c + dc
                        if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols then
                            l[#l + 1] = (nr - 1) * cols + nc
                        end
                    end
                end
            end
            nb[(r - 1) * cols + c] = l
        end
    end
    return nb
end

-- status: 0 hidden, 1 open, 2 known mine
local function newState(rows, cols, total, mine, start)
    local n = rows * cols
    local nb = buildNeighbours(rows, cols)
    local cnt = {}
    for i = 1, n do
        local k = 0
        for _, j in ipairs(nb[i]) do if mine[j] then k = k + 1 end end
        cnt[i] = k
    end
    local S = {
        rows = rows, cols = cols, n = n, total = total, start = start,
        nb = nb, mine = mine, cnt = cnt, status = {},
        stampA = {}, stampB = {}, stamp = 0,
    }
    return S
end

local function setMine(S, i, v)
    if S.mine[i] == v then return end
    S.mine[i] = v
    local d = v and 1 or -1
    local cnt = S.cnt
    for _, j in ipairs(S.nb[i]) do cnt[j] = cnt[j] + d end
end

local function open(S, i)
    local st, cnt, nb = S.status, S.cnt, S.nb
    if st[i] ~= 0 then return end
    if S.mine[i] then error("mine_gen: solver opened a mine") end
    st[i] = 1
    if cnt[i] == 0 then
        local stack, top = { i }, 1
        while top > 0 do
            local k = stack[top]
            stack[top] = nil
            top = top - 1
            for _, j in ipairs(nb[k]) do
                if st[j] == 0 then
                    st[j] = 1
                    if cnt[j] == 0 then
                        top = top + 1
                        stack[top] = j
                    end
                end
            end
        end
    end
end

local function restart(S)
    local st = S.status
    for i = 1, S.n do st[i] = 0 end
    open(S, S.start)
end

-- Builds the constraints of the open numbers that still touch hidden cells.
local function constraints(S)
    local st, cnt, nb = S.status, S.cnt, S.nb
    local cons, at = {}, {}
    local hidden, known = 0, 0
    for i = 1, S.n do
        local s = st[i]
        if s == 0 then
            hidden = hidden + 1
        elseif s == 2 then
            known = known + 1
        elseif cnt[i] > 0 then
            local cells, need = nil, cnt[i]
            for _, j in ipairs(nb[i]) do
                local sj = st[j]
                if sj == 0 then
                    cells = cells or {}
                    cells[#cells + 1] = j
                elseif sj == 2 then
                    need = need - 1
                end
            end
            if cells then
                local k = { cells = cells, need = need, center = i }
                cons[#cons + 1] = k
                at[i] = k
            end
        end
    end
    return cons, at, hidden, known
end

-- Runs the solver from the current status. Returns true when every safe cell
-- is open, false when stuck.
local function solve(S)
    local st, cols, rows = S.status, S.cols, S.rows
    local stampA, stampB = S.stampA, S.stampB
    local progress
    local function settle(cells, as_mine, skip)
        for _, j in ipairs(cells) do
            if st[j] == 0 and not (skip and skip[j] == S.stamp) then
                if as_mine then st[j] = 2 else open(S, j) end
                progress = true
            end
        end
    end
    while true do
        local cons, at, hidden, known = constraints(S)
        if hidden == 0 then return true end
        local remaining = S.total - known
        if remaining == 0 then return true end -- every hidden cell is safe
        progress = false
        -- One number at a time.
        for _, A in ipairs(cons) do
            if A.need == 0 then settle(A.cells, false)
            elseif A.need == #A.cells then settle(A.cells, true) end
        end
        -- Two nearby numbers.
        if not progress then
            for _, A in ipairs(cons) do
                S.stamp = S.stamp + 1
                local sa = S.stamp
                for _, j in ipairs(A.cells) do stampA[j] = sa end
                local ar = floor((A.center - 1) / cols) + 1
                local ac = A.center - (ar - 1) * cols
                for dr = -2, 2 do
                    local br = ar + dr
                    if br >= 1 and br <= rows then
                        for dc = -2, 2 do
                            local bc = ac + dc
                            local B = (bc >= 1 and bc <= cols) and at[(br - 1) * cols + bc]
                            if B and B ~= A then
                                local inter = 0
                                for _, j in ipairs(B.cells) do
                                    if stampA[j] == sa then inter = inter + 1 end
                                end
                                if inter > 0 then
                                    local aOnly = #A.cells - inter
                                    local bOnly = #B.cells - inter
                                    local lo = math.max(0, A.need - aOnly, B.need - bOnly)
                                    local hi = math.min(inter, A.need, B.need)
                                    if lo == hi then
                                        local ma, mb = A.need - lo, B.need - lo
                                        local doA = aOnly > 0 and (ma == 0 or ma == aOnly)
                                        local doB = bOnly > 0 and (mb == 0 or mb == bOnly)
                                        local doI = lo == 0 or lo == inter
                                        if doA or doB or doI then
                                            S.stamp = S.stamp + 1
                                            local sb = S.stamp
                                            for _, j in ipairs(B.cells) do stampB[j] = sb end
                                            for _, j in ipairs(A.cells) do
                                                if st[j] == 0 then
                                                    local inB = stampB[j] == sb
                                                    if inB and doI then
                                                        if lo == 0 then open(S, j) else st[j] = 2 end
                                                        progress = true
                                                    elseif not inB and doA then
                                                        if ma == 0 then open(S, j) else st[j] = 2 end
                                                        progress = true
                                                    end
                                                end
                                            end
                                            if doB then
                                                for _, j in ipairs(B.cells) do
                                                    if st[j] == 0 and stampA[j] ~= sa then
                                                        if mb == 0 then open(S, j) else st[j] = 2 end
                                                        progress = true
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if progress then break end
            end
        end
        -- The mine counter.
        if not progress then
            if remaining == hidden then
                for i = 1, S.n do if st[i] == 0 then st[i] = 2 end end
                return true
            end
            for _, A in ipairs(cons) do
                local rest = hidden - #A.cells
                local restMines = remaining - A.need
                if rest > 0 and (restMines == 0 or restMines == rest) then
                    S.stamp = S.stamp + 1
                    local s = S.stamp
                    for _, j in ipairs(A.cells) do stampA[j] = s end
                    for i = 1, S.n do
                        if st[i] == 0 and stampA[i] ~= s then
                            if restMines == 0 then open(S, i) else st[i] = 2 end
                            progress = true
                        end
                    end
                    break
                end
            end
        end
        if not progress then return false end
    end
end

-- Changes the layout where the solver is stuck. Returns false when it can't.
local function perturb(S)
    local st, nb, mine = S.status, S.nb, S.mine
    local cons = constraints(S)
    if #cons == 0 then return false end
    local A = cons[random(#cons)]
    S.stamp = S.stamp + 1
    local s = S.stamp
    local inS = S.stampA
    local sMines, sSafe = {}, {}
    for _, j in ipairs(A.cells) do
        inS[j] = s
        if mine[j] then sMines[#sMines + 1] = j else sSafe[#sSafe + 1] = j end
    end
    -- Hidden cells no open number sees (first choice), and any other hidden
    -- cell outside the stuck group (fallback).
    local farSafe, farMine, nearSafe, nearMine = {}, {}, {}, {}
    for i = 1, S.n do
        if st[i] == 0 and inS[i] ~= s then
            local seen = false
            for _, j in ipairs(nb[i]) do
                if st[j] == 1 then seen = true break end
            end
            if mine[i] then
                if seen then nearMine[#nearMine + 1] = i else farMine[#farMine + 1] = i end
            elseif seen then nearSafe[#nearSafe + 1] = i
            else farSafe[#farSafe + 1] = i end
        end
    end
    local function take(list)
        local k = random(#list)
        local v = list[k]
        list[k] = list[#list]
        list[#list] = nil
        return v
    end
    local canClear = #sMines <= #farSafe
    local canFill = #sSafe <= #farMine
    local clear
    if canClear and canFill then
        if #sMines ~= #sSafe then clear = #sMines < #sSafe else clear = random(2) == 1 end
    elseif canClear or canFill then
        clear = canClear
    else
        -- Nothing far away: trade with other hidden cells near the frontier.
        for _, j in ipairs(nearSafe) do farSafe[#farSafe + 1] = j end
        for _, j in ipairs(nearMine) do farMine[#farMine + 1] = j end
        if #sMines <= #farSafe and #sMines > 0 then clear = true
        elseif #sSafe <= #farMine and #sSafe > 0 then clear = false
        else return false end
    end
    if clear then
        for _, j in ipairs(sMines) do
            setMine(S, j, false)
            setMine(S, take(farSafe), true)
        end
    else
        for _, j in ipairs(sSafe) do
            setMine(S, j, true)
            setMine(S, take(farMine), false)
        end
    end
    return true
end

local function randomLayout(rows, cols, total, safe_r, safe_c)
    local mine, candidates = {}, {}
    for r = 1, rows do
        for c = 1, cols do
            local i = (r - 1) * cols + c
            mine[i] = false
            if math.abs(r - safe_r) > 1 or math.abs(c - safe_c) > 1 then
                candidates[#candidates + 1] = i
            end
        end
    end
    total = math.min(total, #candidates)
    for k = 1, total do
        local j = random(k, #candidates)
        candidates[k], candidates[j] = candidates[j], candidates[k]
        mine[candidates[k]] = true
    end
    return mine, total
end

-- Returns mine (flat array), ok (true = proved no-guess), stats.
-- on_progress(fraction), optional, is called as the work goes.
function MineGen.generate(rows, cols, total, safe_r, safe_c, on_progress)
    local start = (safe_r - 1) * cols + safe_c
    local stats = { starts = 0, perturbs = 0 }
    local mine, S
    local budget = MineGen.MAX_STARTS * MineGen.MAX_PERTURB
    for _ = 1, MineGen.MAX_STARTS do
        stats.starts = stats.starts + 1
        mine, total = randomLayout(rows, cols, total, safe_r, safe_c)
        S = newState(rows, cols, total, mine, start)
        restart(S)
        local changes = 0
        while true do
            if solve(S) then
                restart(S)
                if solve(S) then return mine, true, stats end
            end
            if changes >= MineGen.MAX_PERTURB or not perturb(S) then break end
            changes = changes + 1
            stats.perturbs = stats.perturbs + 1
            if on_progress and changes % 8 == 0 then
                on_progress(math.min(0.95, stats.perturbs / budget * 10))
            end
        end
    end
    return mine, false, stats
end

-- Exposed for the specs: does the no-trial solver clear `mine` (flat array)
-- from the tap at (r, c)? Also returns the solver's final status array
-- (0 hidden, 1 open, 2 known mine).
function MineGen.isNoGuess(rows, cols, total, mine, r, c)
    local copy = {}
    for i = 1, rows * cols do copy[i] = mine[i] and true or false end
    local S = newState(rows, cols, total, copy, (r - 1) * cols + c)
    if copy[S.start] then return false, S.status end
    restart(S)
    return solve(S), S.status
end

return MineGen
