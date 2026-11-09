-- Old saves keep their mines. (The no-guess guarantees of mine_gen.lua --
-- every preset cleared by the no-trial solver, determinism, speed -- live in
-- test_difficulty_spec.lua.)
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("no-guess mine layouts", function()
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

    it("an old save keeps its mines when loaded", function()
        math.randomseed(7)
        local b = Board:new{ preset = "expert" }
        b:reveal(8, 10)
        local data = b:serialize()
        local b2 = Board:new{ preset = "beginner" }
        assert.is_true(b2:load(data))
        assert.are.same(flat(b), flat(b2))
        assert.is_true(b2.started)
        -- an old save of a not-yet-started game deals on its first tap
        local fresh = Board:new{ preset = "intermediate" }
        local b3 = Board:new{ preset = "beginner" }
        assert.is_true(b3:load(fresh:serialize()))
        assert.are_not.equal("mine", b3:reveal(16, 16))
        assert.are.equal(40, mineCount(b3))
    end)

    it("a save written before 1.4.0 (mine-free cells stored as 0) resumes correctly", function()
        math.randomseed(3)
        local b = Board:new{ preset = "beginner" }
        b:reveal(5, 5)
        local data = b:serialize()
        for r = 1, b.rows do
            for c = 1, b.cols do
                if data.mines[r][c] ~= true then data.mines[r][c] = 0 end
            end
        end
        local b2 = Board:new{}
        assert.is_true(b2:load(data))
        assert.are.equal(10, mineCount(b2))
        for r = 1, b.rows do
            for c = 1, b.cols do
                if b2.state[r][c] == Board.STATE_HIDDEN and not b2.mines[r][c] then
                    assert.are_not.equal("mine", b2:reveal(r, c))
                end
            end
        end
        assert.is_true(b2.win)
    end)
end)
