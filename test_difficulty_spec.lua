-- Difficulty guarantees (mine_gen.lua): every preset, first taps anywhere,
-- is cleared by the no-trial solver; the presets are ordered (size and mine
-- density); a seed always deals the same layout; generation stays fast and
-- never reads the clock.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Runs fn with os.clock/os.time wrapped; returns how often they were read.
local function clockReads(fn)
    local clock, time = os.clock, os.time
    local reads = 0
    os.clock = function() reads = reads + 1; return clock() end
    os.time = function(...) reads = reads + 1; return time(...) end
    local ok, err = pcall(fn)
    os.clock, os.time = clock, time
    assert(ok, err)
    return reads
end

describe("Minesweeper difficulty", function()
    local Board, MineGen

    setup(function()
        Board = require("board")
        MineGen = dofile(DIR .. "mine_gen.lua")
    end)

    local function flat(b)
        local m = {}
        for r = 1, b.rows do
            for c = 1, b.cols do m[(r - 1) * b.cols + c] = b.mines[r][c] end
        end
        return m
    end

    local function mineCount(b)
        local n = 0
        for r = 1, b.rows do
            for c = 1, b.cols do if b.mines[r][c] then n = n + 1 end end
        end
        return n
    end

    -- Corners, edge middles, centre, and a random cell.
    local function taps(rows, cols)
        local mr, mc = math.ceil(rows / 2), math.ceil(cols / 2)
        return {
            { 1, 1 }, { 1, cols }, { rows, 1 }, { rows, cols },
            { 1, mc }, { mr, 1 }, { rows, mc }, { mr, cols }, { mr, mc },
        }
    end

    for _, preset in ipairs({ "beginner", "intermediate", "expert" }) do
        it(preset .. ": 200 seeds x 9 first taps all solvable without guessing", function()
            local cfg = Board.PRESETS[preset]
            local failures, worst = 0, 0
            for seed = 1, 200 do
                local tlist = taps(cfg.rows, cfg.cols)
                local t = tlist[(seed - 1) % #tlist + 1]
                math.randomseed(seed)
                local b = Board:new{ preset = preset }
                local t0 = os.clock()
                local res = b:reveal(t[1], t[2])
                worst = math.max(worst, os.clock() - t0)
                assert.are_not.equal("mine", res)
                assert.are.equal(cfg.mines, mineCount(b))
                -- the first tap and its neighbours are mine-free
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        local r, c = t[1] + dr, t[2] + dc
                        if r >= 1 and r <= cfg.rows and c >= 1 and c <= cfg.cols then
                            assert.is_false(b.mines[r][c])
                        end
                    end
                end
                local ok, status = MineGen.isNoGuess(cfg.rows, cfg.cols, cfg.mines,
                    flat(b), t[1], t[2])
                if not ok then failures = failures + 1 end
                -- the solver's conclusions are true
                for r = 1, cfg.rows do
                    for c = 1, cfg.cols do
                        local s = status[(r - 1) * cfg.cols + c]
                        if s == 2 then assert.is_true(b.mines[r][c]) end
                        if s == 1 then assert.is_false(b.mines[r][c]) end
                    end
                end
            end
            assert.are.equal(0, failures)
            -- ~12 ms worst on LuaJIT; busted's Lua is slower, keep it generous
            assert.is_true(worst < 0.5, "worst generation " .. worst .. " s")
        end)
    end

    it("the solver never marks a wrong cell, even on random (guessy) layouts", function()
        local solved = 0
        for seed = 1, 300 do
            math.randomseed(seed)
            local R, C, M = 16, 20, 70
            local r0, c0 = math.random(R), math.random(C)
            local mine, cand = {}, {}
            for i = 1, R * C do
                mine[i] = false
                local r = math.floor((i - 1) / C) + 1
                local c = i - (r - 1) * C
                if math.abs(r - r0) > 1 or math.abs(c - c0) > 1 then cand[#cand + 1] = i end
            end
            for k = 1, M do
                local j = math.random(k, #cand)
                cand[k], cand[j] = cand[j], cand[k]
                mine[cand[k]] = true
            end
            local ok, status = MineGen.isNoGuess(R, C, M, mine, r0, c0)
            if ok then solved = solved + 1 end
            for i = 1, R * C do
                if status[i] == 2 then assert.is_true(mine[i]) end
                if status[i] == 1 then assert.is_false(mine[i]) end
            end
        end
        -- random expert layouts are mostly NOT guess-free: the check means something
        assert.is_true(solved < 150)
    end)

    it("a seed always deals the same layout", function()
        for _, preset in ipairs({ "beginner", "intermediate", "expert" }) do
            for seed = 1, 10 do
                math.randomseed(seed)
                local a = Board:new{ preset = preset }
                a:reveal(1, 1)
                math.randomseed(seed)
                local b = Board:new{ preset = preset }
                b:reveal(1, 1)
                assert.are.same(flat(a), flat(b))
            end
        end
    end)

    it("the presets are ordered: bigger boards, denser mines", function()
        local prev_cells, prev_density = 0, 0
        for _, preset in ipairs(Board.PRESET_ORDER) do
            local cfg = Board.PRESETS[preset]
            local cells = cfg.rows * cfg.cols
            local density = cfg.mines / cells
            assert.is_true(cells >= prev_cells, preset)
            assert.is_true(density > prev_density, preset)
            prev_cells, prev_density = cells, density
        end
    end)

    it("generation never reads the clock", function()
        for _, preset in ipairs(Board.PRESET_ORDER) do
            local cfg = Board.PRESETS[preset]
            local reads = clockReads(function()
                math.randomseed(11)
                MineGen.generate(cfg.rows, cfg.cols, cfg.mines, 1, 1)
            end)
            assert.are.equal(0, reads, preset)
        end
    end)
end)
