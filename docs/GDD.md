# Few Turns: game design

## High concept
Few Turns is a minimalist portrait arrow puzzle. Each room is a small grid with a start, red dots, a home and some blocks. You get a few arrows to lay on the floor; press Go and one orb rolls, turning on every arrow. Take every dot, then roll home, in one run. Each room gives the fewest arrows that can solve it.

## Why this, and not another "tap the arrows away" game
The store is full of arrow *escape* puzzles (tap arrows in a safe order so they fly off the board). Few Turns is a *routing* puzzle instead: you don't remove arrows, you place them, and you plan a single path that has to do several things at once. It keeps Single Shot's promise (read the room, commit, watch one perfect run) on a grid instead of in angles, so it is exact, readable at a glance and fair by construction.

## Market references
- **Single Shot (ours), Ricochet One:** one committed action, a visible guide, a miss that shows its path.
- **Professor Layton's rolling-ball puzzles, Lightbot, Baba Is You:** placing a few instructions and watching them run.
- **Two Dots, Monument Valley, Alto's Odyssey:** calm palettes, generous space, audio as part of the reward.

## Player promise
You study the room, see the route, spend your few turns exactly where they matter, and watch the orb pick up every dot with a rising run of notes and roll home.

## Core loop
1. Read the room: the start (and its heading), the dots, home, the blocks and the chapter's pieces. TURNS shows how many arrows you get.
2. Lay arrows (tap, tap again to turn, or swipe). The dotted guide shows where the orb rolls, up to its first turn (or two) and a little after.
3. Press Go. The orb rolls one cell at a time, gently speeding up; every dot plays the next note on a pentatonic ladder; home opens when the last dot is taken.
4. Home: ★★★ first try, ★★ within three tries (or first try with a hint), ★ after.
5. Miss: the orb goes back to the start, your arrows stay, the missed path stays faint with a one-line reason. A hint outlines every arrow and draws the way.

## Rules
| Rule | Detail |
|---|---|
| Rolling | One cell per tick, straight on, until something turns it. |
| Arrows | Yours to lay on any free floor cell (cracked floor too). An orb rolling onto one takes its heading. |
| Dots | Taken by rolling over them. |
| Home | Shut until every dot is taken; until then the orb rolls over it. |
| Misses | Into a block, off the board, a shut gate or a hole; two orbs into one cell (but an open home) or through each other; or the board repeating itself. |
| Signs | Printed arrows: they turn the orb like yours, but can't be moved. |
| Bends | `/` and `\`: the orb banks round the corner, whichever way it comes in. |
| Switch and gates | Rolling over a switch flips every gate: shut ones open, open ones shut. |
| Spinners | Point the orb, then turn a quarter clockwise. |
| Portals | In one, out of its twin, same heading. |
| Cracked floor | Holds once: the moment the orb rolls off, it's a hole. |
| Numbered dots | Count only in order; rolling over a later one first does nothing. |
| Two orbs | Roll at the same time and share your arrows. Both must get home. |

The rules live in `game/core/route_sim.gd` and, identically, in `tools/route_lab.py`.

## Progression
- 9 chapters × 40 rooms, gentlest idea first: Path, Signs, Bank, Gate, Spin, Shift, Crumble, Count, Pair. Each introduces one idea, then mixes in earlier ones from about level 16.
- **A learning journey:** level 1 is a tutorial room for the new idea (a card with a live mini-room, then the element spotlit in the room and the way shown once). Every room's winning run really uses the chapter's idea. The first time a chapter brings back an older idea, a short tip says so.
- **Turns climb:** `1 + round((n-1)·4/39)`, from one at level 1 to five at level 40, shown as TURNS over the room.
- **Fairness:** a solver proves each room can be done with exactly its turns and not with fewer; most rooms have exactly one solution, none more than three. Difficulty (the solver's effort) rises strictly from level 2 to 40, and neighbours never play the same shape.
- **Unlocks:** rooms one at a time; a chapter after 15 clears in the previous one.

## Feel
Feedback is tiered by importance:
- **Laying an arrow:** it springs in on a soft tile, a tick, a light haptic. A cell that can't take one shakes red.
- **A turn:** the arrow flashes, a small ring, a tick that climbs in pitch.
- **A dot:** a ring, particles, a pitched note, a medium shake and a haptic pulse.
- **Home:** the ring opens with the last dot; going in brings slow motion, a flash and a heavy shake.
- **A miss:** the orb rolls into the block and springs back, a red ring, a jolt.

Screen shake, vibration and the longer guide can all be toggled in Settings.

## Presentation
- **Layout:** one typeface (Outfit), line icons (Lucide), Single Shot's design system.
- **Colour:** each chapter is a single palette; the backdrop eases between palettes when you change screens.
- **Board:** a soft dot-grid card. Blocks are rounded ink squares; your arrows are coral chevrons on soft tiles; dots are bullseyes; home is a ring that opens.
- **Music:** one synthesised ambient loop per chapter plus a menu theme, in the C-major / A-minor family so the pentatonic dots always fit.

## Monetisation
As in Single Shot (`game/ads/ad_manager.gd`, `game/autoload/store.gd`): a banner with reserved space, one interstitial every 10 wins only on tapping Next, rewarded ads only when asked (a hint, a level key, a one-hour pack trial), 3 free hints a day, and one-time packs (Complete, Supporter, Orb, Theme), level keys and a tip jar.
