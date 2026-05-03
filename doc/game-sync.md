# Game Sync Notes

`Fixed Doors` is intentionally small, but it depends on the shape of the base game's door and interaction scripts. Review this file after Road to Vostok updates that touch doors, interaction, or the player scene.

## Door Interaction

Reference files from the decompiled game:

- `res://Scripts/Door.gd`
- `res://Scripts/Interactor.gd`

The mod relies on normal interactable doors exposing these fields and methods:

- `openAngle`
- `openOffset`
- `isOpen`
- `defaultPosition`
- `defaultRotation`
- `animationTime`
- `Interact()`

The base script currently toggles `isOpen` inside `Interact()` and animates toward `defaultPosition + openOffset` and `defaultRotation + openAngle`. `Fixed Doors` adjusts only `openAngle` while the door is closed, before the game's own interaction call runs.

By default, doors are pass-through unless they are closed. With MCM installed, `Opened Door Collision (Newly Opened Only)` controls settled-open doors, and `Opening/Closing Door Collision` controls doors while they are moving. Normal collision always returns when the door is closed again.

With MCM installed, `Door Obstruction Collision` can stop an opening door at the last non-overlapping pose when its collision shape intersects environment collision, such as map geometry, static props, or another door. Loot items are ignored. Closing doors are not obstruction-blocked, so the player can close a door that opened into an obstruction. Concave door shapes use a reduced obstruction proxy to avoid catching the door frame during normal swings, and `Obstruction Box Scale` controls that temporary query proxy. The real door collision shape is not resized. Interrupted opening doors remain logically open, so the next interaction closes from the paused position.

`Door Collision Logging` writes collision mode transitions and obstruction stops to `user://fixeddoors_collision.log` and the Godot log with the `[FixedDoors][Collision]` prefix. It is session-only and resets to disabled each time the game starts.

## Interactor Lookup

Reference files from the decompiled game:

- `res://Scenes/Core.tscn`
- `res://Scripts/Interactor.gd`

The mod first checks known interactor paths, then falls back to finding a `RayCast3D` named `Interactor` under the current scene. If the player/interactor scene layout changes, update `INTERACTOR_PATHS` in `FixedDoors/Main.gd`.

The mod uses the live interactor target to find the door the player is using. If the player/interactor scene layout changes, update `INTERACTOR_PATHS` in `FixedDoors/Main.gd`.

## Door Side Calculation

The opening direction is based on which side of the closed door plane the player is standing on. The mod reconstructs the door's closed basis from `defaultRotation` and the parent transform, then tests the player position against the door's local Z axis.

If a game update changes door meshes, pivots, or exports `openAngle` on a different child node, review `_player_closed_side()` and `_closed_door_basis()` in `FixedDoors/Main.gd`.

## Door Obstruction Queries

Reference files from the decompiled game:

- `res://Scripts/Door.gd`
- normal hinged door scenes under `res://Modular/Doors/`
- object and container door scenes under `res://Assets/`

The obstruction feature depends on the moving door body exposing its collision shape under an interactable collider. The mod excludes all collision bodies under the moving door and all known player collision bodies, then queries each interactable door `CollisionShape3D` against environment collision layers. Concave shapes are approximated with a reduced box proxy. If door scene ownership or collider layout changes, review `_door_collision_objects()`, `_door_obstruction_shapes()`, and `_shape_obstruction()` in `FixedDoors/Main.gd`.
