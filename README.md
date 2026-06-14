# minesweeper.koplugin

A Minesweeper plugin for [KOReader](https://github.com/koreader/koreader).


## Screenshot

*(Screenshot to be added.)*

## Rules

Reveal all safe cells without hitting a mine. Each revealed cell shows the count of mines in its 8 neighbours. Flag suspected mines. The first tap is always safe.

## Concept

Uncover all safe cells on a grid without detonating any mine. Each uncovered cell
shows the count of mines in its 8 neighbouring cells. Use deduction to flag mines
and clear the board.

## Features

- **Three presets** — Beginner (9×9, 10 mines), Intermediate (16×16, 40 mines), Expert (30×16, 99 mines)
- **Custom grid** — set rows, columns and mine count freely
- **Safe first tap** — the first cell tapped is always safe (mines placed afterwards)
- **Auto-expand** — tapping a 0-cell reveals all adjacent safe cells recursively
- **Flag mode** — toggle between reveal and flag actions
- **Timer** — elapsed time displayed; best times stored per preset
- **Check** — highlights incorrectly flagged cells
- **Auto-save** — in-progress game is restored on next launch

## Controls

| Action | How |
|--------|-----|
| Reveal a cell | Tap it (in reveal mode) |
| Flag / unflag a mine | Tap it (in flag mode) or long-press |
| Toggle reveal / flag mode | Tap the **Flag** button |
| New game | Tap **New game** |
| Change preset | Tap **Preset** |
| Show rules | Tap **Rules** |

## Why e-ink friendly?

Minesweeper is turn-based with no animation required. Cell states (hidden / number /
flagged / mine) map cleanly to simple glyphs renderable on any greyscale display.

## License

GPL-3.0
