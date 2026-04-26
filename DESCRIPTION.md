# Fixed Doors

Fixed Doors makes normal hinged doors in Road to Vostok open away from the player.

## What It Does

In the base game, a door can swing toward you depending on the side you are standing on. This mod changes that interaction so closed doors open to the opposite side of the player whenever possible.

The goal is simple: fewer awkward door swings, less backing up from doors, and a smoother flow through buildings.

## Features

- Normal hinged doors open away from the player
- Open, opening, and closing doors no longer block player movement
- Door bodies stay interactable while pass-through is active
- Optional MCM toggle for opened-door collision
- Keeps the game's existing door interaction flow
- Preserves locked doors, jammed doors, occupied-door checks, sounds, handle animation, and close behavior
- Does not replace `Door.gd`, `Interactor.gd`, or scene files

## Why Use It

Door swings are a small detail, but they matter when moving through tight interiors. Fixed Doors makes door behavior more predictable and keeps doors from blocking narrow paths unless they are fully closed.

If Mod Configuration Menu is installed, `Opened Door Collision` can be enabled to keep open, opening, and closing doors collidable.

It is meant to feel like the same doors, just with the opening direction corrected at the moment you interact with them.

## Compatibility

Fixed Doors should be compatible with mods that do not change door opening direction or door collision behavior.

Other mods that change those same door behaviors may conflict.

## Source Code

https://github.com/MaxandreOgeret/Road-to-Vostok-Fixed-Doors

## Third-Party Asset Notices

Fixed Doors contains no bundled third-party assets.
