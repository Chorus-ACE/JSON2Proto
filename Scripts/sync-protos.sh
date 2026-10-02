#!/bin/sh
set -eu

# Run from any directory. The sibling checkout is the default destination.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination=${1:-"$root/../SekaiKit/SekaiKit/Protobuf"}
mkdir -p "$destination"
for name in Character Event Card; do
    cp "$root/SekaiProtoDef/$name.proto" "$destination/$name.proto"
done
