# Fixed Doors

Fixed Doors makes normal hinged doors in Road to Vostok open away from the player.

## What It Does

In the base game, a door can swing toward you depending on the side you are standing on. This mod changes that interaction so closed doors open to the opposite side of the player whenever possible.

The goal is simple: fewer awkward door swings, less backing up from doors, and a smoother flow through buildings.

## Features

- Normal hinged doors open away from the player
- Open, opening, and closing doors no longer block player movement
- Door bodies stay interactable while pass-through is active
- Optional MCM controls for opened-door, moving-door, door-obstruction collision, obstruction proxy scale, and collision logging
- Keeps the game's existing door interaction flow
- Preserves locked doors, jammed doors, occupied-door checks, sounds, handle animation, and close behavior
- Does not replace `Door.gd`, `Interactor.gd`, or scene files

## Why Use It

Door swings are a small detail, but they matter when moving through tight interiors. Fixed Doors makes door behavior more predictable and keeps doors from blocking narrow paths unless they are fully closed.

If Mod Configuration Menu is installed, collision can be configured separately with `Opened Door Collision (Newly Opened Only)`, `Opening/Closing Door Collision`, `Door Obstruction Collision`, and `Obstruction Box Scale`.

When `Door Obstruction Collision` is enabled, opening doors pause at the last non-overlapping position if they hit environment collision, such as map geometry, static props, or another door. Closing doors are not obstruction-blocked, so the player can close a door that opened into an obstruction. Loot items are ignored. Concave door shapes use a reduced obstruction proxy to avoid catching the door frame during normal swings. `Obstruction Box Scale` controls that temporary query proxy, not the real door collision shape. Interrupted opening doors remain logically open.

`Door Collision Logging` can be enabled for troubleshooting collision mode changes and obstruction stops in `user://fixeddoors_collision.log` and the Godot log. It is session-only and resets to disabled each time the game starts.

It is meant to feel like the same doors, just with the opening direction corrected at the moment you interact with them.

## Compatibility

Fixed Doors should be compatible with mods that do not change door opening direction or door collision behavior.

Other mods that change those same door behaviors may conflict.

## Source Code

https://github.com/MaxandreOgeret/Road-to-Vostok-Fixed-Doors

## Third-Party Asset Notices

Fixed Doors contains no bundled third-party assets.

The packaged VMZ includes `FixedDoors_LICENSE` and `FixedDoors_NOTICE` for license and attribution details.
