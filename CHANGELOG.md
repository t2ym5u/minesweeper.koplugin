# Changelog

All notable changes to this project will be documented in this file.

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

