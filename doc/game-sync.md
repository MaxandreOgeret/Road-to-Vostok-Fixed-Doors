# Game Sync Notes

`Fixed Doors` is intentionally small, but it depends on the shape of the base game's door and interaction scripts. Review this file after Road to Vostok updates that touch doors, interaction, or the player scene.

## Door Interaction

Reference files from the decompiled game:

- `res://Scripts/Door.gd`
- `res://Scripts/Interactor.gd`

The mod relies on normal interactable doors exposing these fields and methods:

- `openAngle`
- `isOpen`
- `defaultPosition`
- `defaultRotation`
- `Interact()`
- `UpdateTooltip()`

The base script currently toggles `isOpen` inside `Interact()` and animates toward `defaultRotation + openAngle`. `Fixed Doors` adjusts only `openAngle` while the door is closed, before the game's own interaction call runs. Locks, jammed doors, occupied doors, audio, handle motion, and close behavior stay owned by the base script.

## Interactor Lookup

Reference files from the decompiled game:

- `res://Scenes/Core.tscn`
- `res://Scripts/Interactor.gd`

The mod first checks known interactor paths, then falls back to finding a `RayCast3D` named `Interactor` under the current scene. If the player/interactor scene layout changes, update `INTERACTOR_PATHS` in `FixedDoors/Main.gd`.

## Door Side Calculation

The opening direction is based on which side of the closed door plane the player is standing on. The mod reconstructs the door's closed basis from `defaultRotation` and the parent transform, then tests the player position against the door's local Z axis.

If a game update changes door meshes, pivots, or exports `openAngle` on a different child node, review `_player_closed_side()` and `_closed_door_basis()` in `FixedDoors/Main.gd`.
