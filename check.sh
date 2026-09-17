#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc Sources/Recorta/PhotoEngine.swift Sources/Recorta/CropGeometry.swift Checks/PhotoEngineChecks.swift -o .build/checks/PhotoEngineChecks
.build/checks/PhotoEngineChecks
