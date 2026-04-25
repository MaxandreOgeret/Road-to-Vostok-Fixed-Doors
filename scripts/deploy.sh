#!/usr/bin/env bash
set -euo pipefail

mods_dir="${RTV_MODS_DIR:-$HOME/.steam/debian-installation/steamapps/common/Road to Vostok/mods}"
vmz_artifact="${1:-FixedDoors.vmz}"

"$(dirname "$0")/build_vmz.sh" "$vmz_artifact"
mkdir -p "$mods_dir"
cp "$vmz_artifact" "$mods_dir/"

echo "Deployed $vmz_artifact to $mods_dir"
