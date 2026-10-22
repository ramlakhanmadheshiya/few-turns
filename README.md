# Few Turns

*A quiet arrow puzzle.* Lay a few arrows on the floor, press Go, and watch one orb roll through every red dot and home. Every room gives you the fewest turns that can solve it.

Made with Godot 4.7.2 (GDScript, Compatibility renderer, so it also runs on the web). It is portrait-first and works with touch, mouse and keyboard. A Brainnova Studio game, by Ramlakhan Madheshiya with Claude as AI co-developer.

**Play / download:** https://theramlakhan.com/BrainnovaStudio/games/few-turns/ (Android APK, and play in the browser once the game is in testing).

## The game

- **The rules.** Each room has a start (a ring with a little pointer), red dots, home (a ring that stays shut until every dot is taken) and blocks. The orb rolls straight, one cell at a time, and turns on every arrow. It must take every dot and then roll into home. Rolling into a block, off the board, or round in circles (the board repeating itself) is a miss.
- **Arrows.** TURNS shows how many arrows the room gives. Tap a free cell to lay one (it points the way the orb would turn there); tap again to turn it a quarter, and after four turns it's taken back. Swipe on a cell to point its arrow straight away. Restart clears them all.
- **The guide.** A dotted line shows where the orb rolls, up to its first turn and two cells on (two turns with the Longer guide, on by default), ending in a cross where it would crash.
- **One run per try.** A miss puts the orb back at the start; the arrows and the missed path (with the reason: "Hit a block · 2 dots left") stay, so the next try can adjust.
- **Stars:** first try ★★★, within three tries (or first try with a hint) ★★, after that ★.
- **9 chapters × 40 rooms = 360 rooms.** Each chapter has its own palette, music and a chapter card with a live mini-room, opens with a tutorial room (a card with the live scene, then the new element spotlit and the way shown once), and mixes in earlier ideas from about level 16:

  | # | Chapter | Colours | New idea |
  |---|---|---|---|
  | 1 | Path | warm cream | arrows, dots, blocks, home (hands-on tutorial with an animated hand) |
  | 2 | Signs | mint | printed signs turn the orb too, and can't be moved |
  | 3 | Bank | sky | bends (`/` and `\`) bank the orb round the corner |
  | 4 | Gate | sage | rolling over the switch flips every gate |
  | 5 | Spin | rose | spinners point the orb, then turn a quarter clockwise |
  | 6 | Shift | dusk violet | portals carry the orb across, same heading |
  | 7 | Crumble | amber night | cracked floor crumbles into a hole once the orb rolls off it |
  | 8 | Count | midnight | numbered dots count only in order |
  | 9 | Pair | indigo night | two orbs roll at once and share your arrows; both must get home without meeting |

- **Pacing.** Turns climb `1 + round((n-1)·4/39)`: one at level 1, five at level 40. Within each turn count, rooms get harder level by level (difficulty rises strictly from level 2 to 40).
- **Hints** show the solving path and outline where each arrow goes (arrows that aren't part of it are taken back). 3 free hints a day; with none left, the game asks before a rewarded ad for +1 (free if no ad is available).
- **After a clear:** Next, Watch (replays your run), Share, Again and Levels. Share renders a 1080×1350 card of the room with your run, stars and a QR code.
- **Progress:** rooms unlock one at a time; a chapter opens after 15 clears in the one before. Level keys open any room early.
- **Shop, ads, settings, saving and sharing** work exactly as in Single Shot (`game_1/single-shot`): supporter, orb, theme and complete packs, level keys, a tip jar; a bottom banner with reserved space, rewarded ads only on request, one full-screen ad after every 10 wins on tapping Next.

### Controls

| Input | Action |
|---|---|
| Tap a cell (touch or mouse) | Lay an arrow, or turn it (the fifth tap takes it back) |
| Swipe on a cell | Point that cell's arrow the way of the swipe |
| Go button, Space or G | Roll (Space while rolling fast-forwards; so does tapping the room) |
| Arrow keys / WASD | Move the cell cursor |
| Enter or E · Backspace or X | Tap the cursor's cell · take its arrow back |
| R | Restart (clears the arrows) |
| H | Hint |
| Esc, or Back on Android | Back |

## Run

```sh
./play.sh            # launches the game window directly (no editor)
```

## Check

```sh
./tests/run_all.sh                                       # rules, every level, UI flow, boot smoke
godot --path . res://tests/capture.tscn -- /tmp/ft_shots  # screenshots of every screen (not committed)
.venv/bin/python -I tools/route_lab.py --check           # re-solve every shipped level (slow)
```

## How it works

| Piece | File |
|---|---|
| The rules: a deterministic grid simulation, shared by gameplay, the guide, hints, chapter art and tests | `game/core/route_sim.gd` |
| Board: drawing, laying arrows, the guide, playback and feel (shake, slow motion going home, pentatonic dots, rings, particles, haptics) | `game/board/board.gd` |
| App shell, screens, design system and palettes | `game/ui/` |
| Save data, level catalogue and unlocks, audio, haptics, web rules | `game/autoload/` |
| Level generator and solver (Python, the same rules) | `tools/route_lab.py` |
| Audio synthesiser | `tools/synth_audio.py` (see `docs/AUDIO.md`) |

**How the levels are made** (`tools/route_lab.py`). The generator rolls an orb across an empty board and lays the level down under it: arrows where it turns, the chapter's features (signs, bends, spinners, a switch and the gates it opens, portals, cracked floor), dots on cells it passes once, home where it stops, and for Pair a second start that joins the run at one of its arrows. Decoys and blocks go on cells the run never touches.

Then the solver takes over. It explores every way to lay arrows, deciding each arrow the first time an orb rolls onto a free cell (no arrow, or one of four directions), so only cells the orb actually visits are tried, and it remembers board states to cut loops. While a cheaper solution, or a different one with the same turns, exists, a block goes on a cell only that solution uses. A room is kept only if it then needs exactly the turns its level gives, has at most three solutions (most have exactly one), and its winning run really uses the chapter's idea.

Picking the 40: candidates for each turn count are sorted by search effort (how hard the solver worked, how unique the answer, how many dots and how long the run) and spread over the upper range, so effort rises level by level; neighbours never play the same shape. The opening rooms of Signs, Bank, Spin, Shift and Count are hand-made, and verified by the solver like the rest.

```sh
.venv/bin/python tools/route_lab.py        # all chapters (a few minutes)
.venv/bin/python tools/route_lab.py ch3    # one chapter
```

`tests/levels_test.gd` replays every stored solution through the GDScript rules and checks the tick count matches the generator's, so the two implementations can't drift apart.

## Build & publish

Every push to `main` runs `.github/workflows/build.yml`: it runs the tests, exports a signed Android APK and App Bundle and a web build (with the studio's slim engine), and ships them to Brainnova Studio with `tools/ship.sh`: the game page with the APK at `theramlakhan.com/BrainnovaStudio/games/few-turns/`, help and privacy from `web/`, and the browser build at `/BrainnovaStudio/play/few-turns/`. In the browser the music isn't in the pack; it streams in as Ogg Vorbis.

APK signing uses `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEYSTORE_ALIAS` (set by `../../game-keys.sh setup game_4/few-turns`).

Store graphics (`store/`): `godot --path . res://tests/capture.tscn -- build/store/raw --store`, then `.venv/bin/python -I tools/store_art.py` (needs pillow); icons with `godot --headless --path . -s res://tools/render_icon.gd`; the feature graphic with `godot --path . --resolution 1024x500 res://tools/render_feature_graphic.tscn`.

## Credits

| Asset | Source | Licence |
|---|---|---|
| Font: [Outfit](https://github.com/google/fonts/tree/main/ofl/outfit) | Google Fonts | SIL OFL 1.1, `assets/fonts/OFL.txt` |
| Icons: [Lucide](https://lucide.dev) | lucide-static 0.460.0 | ISC, `assets/icons/LICENSE.txt` |
| Music and sound effects | Made by `tools/synth_audio.py` (shared with Single Shot's instruments, with Few Turns' own melodies), no samples | Released with the project |
| QR code on the share card | Generated with [segno](https://github.com/heuer/segno) | Generated output |

The game-dev agent skills used while building this are in `.claude/skills/`. They come from [GodotPrompter](https://github.com/jame581/GodotPrompter) (MIT), [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) (Apache-2.0) and [godot-skills](https://github.com/vl4dt/godot-skills) (MIT).
