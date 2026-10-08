#!/usr/bin/env bash
# Копирует мод в папку модов Victoria 3 внутри Proton-префикса.
# Игра под Proton читает Documents из префикса; префикс появляется после первого запуска игры.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="$HOME/.local/share/Steam/steamapps/compatdata/529340/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Victoria 3"
NAME="sharp_terrain_low_shaders"

[ -d "$DST" ] || { echo "Папка игры в префиксе не найдена: $DST" >&2; echo "Запусти Victoria 3 через Steam один раз, чтобы Proton её создал." >&2; exit 1; }
pgrep -f "Paradox Launcher.exe" >/dev/null && echo "Внимание: лаунчер запущен, перезапусти его после установки." >&2

mkdir -p "$DST/mod/$NAME"
rm -rf "$DST/mod/$NAME/gfx" "$DST/mod/$NAME/.metadata"
cp -r "$SRC/gfx" "$SRC/.metadata" "$DST/mod/$NAME/"
[ -f "$SRC/thumbnail.png" ] && cp "$SRC/thumbnail.png" "$DST/mod/$NAME/thumbnail.png"

echo "Установлено в $DST/mod/$NAME"
echo "Дальше: в лаунчере Victoria 3 добавь 'Sharp Terrain on Low Shader Quality' в плейсет и поставь Shader Quality = Low в игре."
