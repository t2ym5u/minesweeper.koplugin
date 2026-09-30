# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps: the first says which cell is about to give, the
  second acts on it. A cell that contradicts the solution is always reported
  before a fresh one is revealed.
- The mines are only placed on the first tap, so the button stays quiet
  until the game has actually started — before that there is no solution to
  reason from and it would happily "prove" any cell safe.

