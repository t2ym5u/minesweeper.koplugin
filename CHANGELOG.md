# Changelog

All notable changes to this project will be documented in this file.

## [1.4.0] - 2026-11-05

### Changed
- No game ever needs a guess any more. Mines are still placed after the
  first tap (which, with its neighbours, stays mine-free), but now in a
  layout that can be cleared by deduction alone: one number at a time, two
  nearby numbers together, and the mine counter. Before, only 77% of
  Beginner, 55% of Intermediate and 3% of Expert games could be cleared
  without guessing; now all of them can, wherever the first tap is. The mine
  counts are unchanged. The rules say so.

### Fixed
- Resuming a saved game no longer makes every cell a mine: the first tap
  after reopening the game always exploded. Games saved by older versions
  resume correctly too.
- README: the Expert preset is 20×16 with 70 mines, and the list no longer
  mentions a custom grid or best times the game does not have.

## [1.3.5] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.3.4] - 2026-11-04

### Fixed
- The game is called « Démineur » in French and « Buscaminas » in Spanish
  (it was shown as "Minesweeper").

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.3.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.3.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.3.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.3.0] - 2026-10-30

### Added
- "New game" once the game is won or lost: the action bar shows it in place
  of Flag, Check and Hint, so the next game no longer needs the menu.
- The rules now explain the gestures: tap to uncover, long-press (or Flag
  mode) to flag, tap a satisfied number to uncover its other neighbours.

### Changed
- Redesigned play screen, in line with the other games: the standard title
  bar and menu, a full-width action bar, a larger board that fills the
  available room, and one frame around it. The status line reads "size ·
  difficulty · Mines: n · Time: t" and wraps in landscape instead of being
  cut off; flag mode is shown on its button only.
- Title-bar menu in the same order as every other game: New game,
  "Difficulty: Beginner" (was "Preset: Beginner" in a separate pop-up),
  Rules.
- New README screenshot.

### Fixed
- The difficulty names (Beginner, Intermediate, Expert) were never
  translated.
- A flagged cell was drawn like an uncovered blank; it now keeps the covered
  shade under its flag.
- Numbers and flags overflowed the small cells of the larger boards on
  high-DPI screens. They are now fitted to the cell.
- Using Hint wiped the saved game: the board was saved as nothing.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps: the first says which cell is about to give, the
  second acts on it. A cell that contradicts the solution is always reported
  before a fresh one is revealed.
- The mines are only placed on the first tap, so the button stays quiet
  until the game has actually started — before that there is no solution to
  reason from and it would happily "prove" any cell safe.

