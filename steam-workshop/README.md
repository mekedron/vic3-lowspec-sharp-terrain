# Steam Workshop publishing kit

Everything needed for the Steam Workshop and Paradox Mods listings. Nothing here ships with the mod
itself — the mod is `.metadata/`, `thumbnail.png` and `gfx/` in the repository root.

| File | Where it goes |
| --- | --- |
| `description-en.txt` | Workshop item description (BBCode) |
| `description-ru.txt` | Russian version of the same description |
| `description-paradoxmods-en.txt` | same text without BBCode, for the Paradox Mods site |
| `description-paradoxmods-ru.txt` | Russian version without BBCode |
| `short-description-en.txt` | Launcher / Paradox Mods short description, under 200 chars |
| `short-description-ru.txt` | Russian short description, under 200 chars |
| `make_thumbnail.py` | rebuilds `thumbnail.png`: a title card, or BEFORE / AFTER from two screenshots |

The Paradox Mods files are **generated** from the Steam ones by `tools/bbcode_to_plain.py`;
edit the BBCode version and re-run it rather than editing them directly.

**Do not use `[code]` in the Steam files.** Steam has no inline code tag — it renders `[code]` as a
full-width block. Identifiers are written as plain text instead.

## Listing metadata

* **Title:** Sharp Terrain on Low Shader Quality
* **Game:** Victoria 3 (app 529340)
* **Tags:** Graphics, Fixes, Utilities — same as `.metadata/metadata.json`
* **Version:** 1.0.0, `supported_game_version` 1.13.*
* **Visibility:** public

The Russian description must stay under Steam's 8000 **byte** limit (Cyrillic is two bytes per
character); a longer text fails silently and the page keeps showing English.

## Thumbnail

`thumbnail.png` in the mod root, referenced by `"picture"` in the metadata. Without screenshots
`make_thumbnail.py` draws a title card. With two screenshots of the same view on Shader Quality
Low, vanilla first and the mod second:

    steam-workshop/make_thumbnail.py before.png after.png [x y w h]

it crops the same window out of both (default: the middle of the screen; pass a window that keeps
the HUD out) and stacks them as BEFORE / AFTER under the title. The output is quantised to 256
colours and carries no metadata from the screenshots.
