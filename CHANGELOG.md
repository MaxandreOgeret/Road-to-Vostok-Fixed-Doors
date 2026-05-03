# Changelog

## Unreleased

- Changed obstruction handling to block opening doors only, so closing can recover doors that opened into environment props.
- Fixed obstruction handling so doors that are already overlapping an obstruction can still move out of it before later clear-to-block transitions are enforced.
- Made `Door Collision Logging` session-only so it resets to disabled on game start.

## 1.2.1

- Restricted VMZ packaging to the runtime mod files plus prefixed `FixedDoors_LICENSE` and `FixedDoors_NOTICE` attribution files.

## 1.2.0

- Added `Door Obstruction Collision`, an MCM toggle that stops moving doors when their collision shape intersects environment collision. Loot items are ignored, and concave door shapes use a reduced obstruction proxy to avoid catching the door frame during normal swings.
- Added `Obstruction Box Scale`, an MCM slider for the reduced obstruction query proxy used by concave door collision shapes.
- Blocked opening doors stay logically open, and blocked closing doors stay logically closed, so the next interaction reverses from the paused position.
- Added `Door Collision Logging`, an MCM toggle for Godot log diagnostics around door collision mode changes and obstruction stops.

## 1.1.0

- Added MCM toggles for settled-open door collision and opening/closing door collision.
- Clarified that opened-door collision only applies to newly opened doors.
- Fixed collision setting changes not being applied to the next door interaction in some cases.
- Fixed opening/closing door collision detection so the MCM toggle applies while doors are moving.

## 1.0.1

- Doors are only collidable when fully closed while still remaining interactable.
- Relicensed the project as GPL-3.0.
- Updated repository and ModWorkshop descriptions.

## 1.0.0

- Initial release.
- Doors now open away from the player when opened through the normal interaction flow.
