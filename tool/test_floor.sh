#!/usr/bin/env bash
# Prueba los dos paquetes de pub.dev contra el suelo que declaran: Flutter 3.32
# y Dart 3.8.
#
# No basta con `melos run verify`: el workspace exige Dart 3.9, así que con
# 3.32 ni resuelve. Y quien instala el paquete no tiene el workspace: lo
# resuelve suelto. Esto hace lo mismo que él —copia cada paquete fuera, quita
# `resolution: workspace` y apunta `nativ_maps_flutter` al `nativ_maps` local—,
# y pasa el análisis estricto y las pruebas.
#
# La 0.5.1 no compilaba en 3.32 y nada lo detectó hasta que se probó así.
#
#   tool/test_floor.sh <directorio bin de Flutter 3.32>
#   tool/test_floor.sh ~/fvm/versions/3.32.0/bin
set -euo pipefail

FLUTTER_BIN="${1:?uso: tool/test_floor.sh <directorio bin de Flutter 3.32>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$FLUTTER_BIN/flutter" --version | head -2

for pkg in nativ_maps nativ_maps_flutter; do
  rsync -a --exclude .dart_tool --exclude build --exclude 'test/live/respuestas' \
    "$ROOT/packages/$pkg/" "$WORK/$pkg/"
  sed -i.bak '/^resolution: workspace$/d' "$WORK/$pkg/pubspec.yaml"
done
printf '\ndependency_overrides:\n  nativ_maps:\n    path: ../nativ_maps\n' \
  >> "$WORK/nativ_maps_flutter/pubspec.yaml"

echo "== nativ_maps"
(
  cd "$WORK/nativ_maps"
  "$FLUTTER_BIN/dart" pub get
  "$FLUTTER_BIN/dart" analyze --fatal-infos --fatal-warnings
  "$FLUTTER_BIN/dart" test
)

echo "== nativ_maps_flutter"
(
  cd "$WORK/nativ_maps_flutter"
  "$FLUTTER_BIN/flutter" pub get
  "$FLUTTER_BIN/flutter" analyze --fatal-infos
  "$FLUTTER_BIN/flutter" test
)

echo "El suelo compila y pasa."
