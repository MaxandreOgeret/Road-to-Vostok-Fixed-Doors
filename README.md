# Fixed Doors

`Fixed Doors` is a `Road to Vostok` mod that makes normal hinged doors open away from the player.

## Overview

The mod leaves the base door script in charge of locking, jamming, occupied-door checks, audio, handle motion, and animation. When the player is looking at a closed door, the mod adjusts that door's `openAngle` before the game's own interaction call runs, so the next open swing moves to the side opposite the player.

Doors still close through the game's normal behavior. Locked, jammed, and occupied doors are not bypassed.

## Compatibility

`Fixed Doors` does not override `Door.gd`, `Interactor.gd`, or any scene files. It only changes a targeted closed door's `openAngle` immediately before interaction.

Because it changes live door state, other mods that also rewrite door opening direction may conflict.

## Repository Layout

The packaged mod consists of `mod.txt` and the `FixedDoors/` directory. Runtime logic lives in `FixedDoors/Main.gd`.

The repository also includes [doc/game-sync.md](doc/game-sync.md), which documents the parts of the mod that intentionally depend on decompiled game logic and should be reviewed after a game update.

## Build

Create the mod archive from the repository root with:

```bash
./scripts/build_vmz.sh
```

That produces `FixedDoors.vmz`, which is a regular zip archive with the `.vmz` extension. The root of the archive contains `mod.txt` and the `FixedDoors/` directory.

The build also produces `FixedDoors.zip`, which is a regular zip file that contains the `.vmz` archive for distribution on sites that expect `.zip` uploads.

Deploy the fresh `.vmz` straight into the local game mods folder with:

```bash
./scripts/deploy.sh
```

By default this copies to `~/.steam/debian-installation/steamapps/common/Road to Vostok/mods/`. Override the destination by setting `RTV_MODS_DIR`.

## CI

GitHub Actions runs linting and build checks on pushes and pull requests:

- `./scripts/lint.sh` runs `gdlint` and `gdformat --check`
- `./scripts/build_vmz.sh` builds `FixedDoors.vmz` and `FixedDoors.zip`
- the workflow uploads the built `.vmz` as the CI artifact

## Install

Copy `FixedDoors.vmz` into the Road to Vostok mods folder, then restart the game completely.

By default the deploy script copies to:

```text
~/.steam/debian-installation/steamapps/common/Road to Vostok/mods/
```

Override that destination with `RTV_MODS_DIR`.

## Requirements

The mod requires `Road to Vostok` and the community mod loader format used by the game.

## Licensing

The repository code is MIT licensed. See [LICENSE](LICENSE).

## References

The loader format and installation details are documented at <https://github.com/ametrocavich/vostok-mod-loader>.
