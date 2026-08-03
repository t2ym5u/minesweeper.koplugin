local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("MinesweeperBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    local S_HIDDEN   = Board and Board.STATE_HIDDEN   or 0
    local S_REVEALED = Board and Board.STATE_REVEALED or 1
    local S_FLAGGED  = Board and Board.STATE_FLAGGED  or 2

    -- Re-read constants after setup (setup runs before these are used)
    before_each(function()
        S_HIDDEN   = Board.STATE_HIDDEN
        S_REVEALED = Board.STATE_REVEALED
        S_FLAGGED  = Board.STATE_FLAGGED
    end)

    local function newBoard(preset)
        math.randomseed(42)
        return Board:new({ preset = preset or "beginner" })
    end

    describe("construction", function()
        it("creates a beginner board (9×9, 10 mines)", function()
            local b = newBoard()
            assert.are.equal(9,  b.rows)
            assert.are.equal(9,  b.cols)
            assert.are.equal(10, b.mine_count)
        end)

        it("is not started before the first reveal", function()
            local b = newBoard()
            assert.is_false(b.started)
            assert.is_false(b.game_over)
            assert.is_false(b.win)
        end)

        it("all cells start as HIDDEN", function()
            local b = newBoard()
            for r = 1, b.rows do
                for c = 1, b.cols do
                    assert.are.equal(S_HIDDEN, b.state[r][c])
                end
            end
        end)
    end)

    describe("reveal", function()
        it("starts the game on first reveal", function()
            local b = newBoard()
            b:reveal(5, 5)
            assert.is_true(b.started)
        end)

        it("first reveal is never a mine (safe zone)", function()
            -- first reveal must return "ok" or "win", never "mine"
            local b = newBoard()
            local result = b:reveal(5, 5)
            assert.is_not_equal("mine", result)
            assert.is_false(b.game_over)
        end)

        it("reveals the clicked cell", function()
            local b = newBoard()
            b:reveal(5, 5)
            assert.are.equal(S_REVEALED, b.state[5][5])
        end)

        it("returns 'already' for an already-revealed cell", function()
            local b = newBoard()
            b:reveal(5, 5)
            local result = b:reveal(5, 5)
            assert.are.equal("already", result)
        end)

        it("sets game_over on mine reveal", function()
            local b = newBoard()
            b:reveal(5, 5)  -- place mines, first reveal is safe
            -- find a mine to reveal
            local mr, mc
            for r = 1, b.rows do
                for c = 1, b.cols do
                    if b.mines[r][c] and b.state[r][c] == S_HIDDEN then
                        mr, mc = r, c; break
                    end
                end
                if mr then break end
            end
            assert.is_not_nil(mr, "board must have hidden mines after first reveal")
            local result = b:reveal(mr, mc)
            assert.are.equal("mine", result)
            assert.is_true(b.game_over)
        end)
    end)

    describe("toggleFlag", function()
        it("flags a hidden cell", function()
            local b = newBoard()
            b:toggleFlag(1, 1)
            assert.are.equal(S_FLAGGED, b.state[1][1])
            assert.are.equal(1, b.flags_placed)
        end)

        it("un-flags a flagged cell", function()
            local b = newBoard()
            b:toggleFlag(1, 1)
            b:toggleFlag(1, 1)
            assert.are.equal(S_HIDDEN, b.state[1][1])
            assert.are.equal(0, b.flags_placed)
        end)

        it("cannot flag a revealed cell", function()
            local b = newBoard()
            b:reveal(5, 5)
            local state_before = b.state[5][5]
            b:toggleFlag(5, 5)
            assert.are.equal(state_before, b.state[5][5])
        end)
    end)

    describe("getRemainingMines", function()
        it("equals mine_count at start", function()
            local b = newBoard()
            assert.are.equal(b.mine_count, b:getRemainingMines())
        end)

        it("decreases when a flag is placed", function()
            local b = newBoard()
            b:toggleFlag(1, 1)
            assert.are.equal(b.mine_count - 1, b:getRemainingMines())
        end)
    end)

    describe("revealAllMines", function()
        it("reveals all mine cells", function()
            local b = newBoard()
            b:reveal(5, 5)
            b.game_over = true
            b:revealAllMines()
            for r = 1, b.rows do
                for c = 1, b.cols do
                    if b.mines[r][c] then
                        assert.are.equal(S_REVEALED, b.state[r][c])
                    end
                end
            end
        end)
    end)

    describe("serialize / load", function()
        it("round-trips board state after a move", function()
            local b = newBoard()
            b:reveal(5, 5)
            b:toggleFlag(1, 1)
            local data = b:serialize()

            local b2 = Board:new()
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.rows,         b2.rows)
            assert.are.equal(b.mine_count,    b2.mine_count)
            assert.are.equal(b.flags_placed,  b2.flags_placed)
            assert.are.equal(b.started,       b2.started)
            assert.are.equal(S_REVEALED,      b2.state[5][5])
            assert.are.equal(S_FLAGGED,       b2.state[1][1])
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
