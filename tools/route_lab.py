#!/usr/bin/env python3
"""Few Turns level lab: the rules, an exhaustive solver, and the level generator.

The rules here are the same as game/core/route_sim.gd (tests/levels_test.gd replays
every stored solution in GDScript and checks the tick count matches), so the two
must change together.

    python3 tools/route_lab.py                 build every chapter into content/levels/
    python3 tools/route_lab.py ch3             build one chapter
    python3 tools/route_lab.py --check         re-solve every shipped level (slow)

The grid: x to the right, y down. Directions 0 right, 1 down, 2 left, 3 up; turning
clockwise is d + 1.

A run, tick by tick (see `Sim.tick`):
1. every moving orb leaves its cell (a cracked cell it leaves crumbles into a hole);
2. it moves one cell on. Off the board, into a block, a closed gate or a hole: crash.
   Two orbs into the same cell (but an open home), or through each other: crash;
3. a portal sends it to its twin portal, same heading;
4. it takes a dot (numbered dots only in order);
5. home takes it once every dot is taken (until then it rolls over home);
6. it turns: a placed arrow or a sign points it, a spinner points it and then turns
   90 degrees clockwise, a bend (/ or \\) deflects it;
7. a switch flips every gate (open <-> closed).
The run is won when every orb is home, lost on a crash, and lost if the board ever
repeats itself (the orb is going round in circles) or after MAX_TICKS.
"""

import json
import math
import os
import random
import sys
from multiprocessing import Pool

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "content", "levels")

DX = (1, 0, -1, 0)
DY = (0, 1, 0, -1)
# Bends: 0 is "/", 1 is "\".
BEND = ((3, 2, 1, 0), (1, 0, 3, 2))
MAX_TICKS = 400
LEVELS_PER_CHAPTER = 40

WIN, LOSE, GOING = 1, 2, 0


# --- Rules --------------------------------------------------------------------

class Board:
    """The fixed parts of a level, as flat lookups by cell index."""

    def __init__(self, lv):
        self.w = lv["w"]
        self.h = lv["h"]
        n = self.w * self.h
        self.blocks = bytearray(n)
        for x, y in lv.get("blocks", []):
            self.blocks[y * self.w + x] = 1
        self.signs = {y * self.w + x: d for x, y, d in lv.get("signs", [])}
        self.spinners = {}
        self.spin0 = []
        for i, (x, y, d) in enumerate(lv.get("spinners", [])):
            self.spinners[y * self.w + x] = i
            self.spin0.append(d)
        self.bends = {y * self.w + x: k for x, y, k in lv.get("bends", [])}
        self.switches = {y * self.w + x for x, y in lv.get("switches", [])}
        self.gates = {y * self.w + x: o for x, y, o in lv.get("gates", [])}
        self.portals = {}
        for x1, y1, x2, y2 in lv.get("portals", []):
            a, b = y1 * self.w + x1, y2 * self.w + x2
            self.portals[a] = b
            self.portals[b] = a
        self.cracks = {}
        for i, (x, y) in enumerate(lv.get("cracks", [])):
            self.cracks[y * self.w + x] = i
        self.dots = {}
        self.ordered = False
        for i, d in enumerate(lv.get("dots", [])):
            order = d[2] if len(d) > 2 else 0
            self.dots[d[1] * self.w + d[0]] = (i, order)
            if order:
                self.ordered = True
        self.all_dots = (1 << len(self.dots)) - 1
        hx, hy = lv["home"]
        self.home = hy * self.w + hx
        self.starts = [(s[1] * self.w + s[0], s[2]) for s in lv["starts"]]
        start_cells = {c for c, _ in self.starts}
        # Where the player may put an arrow: plain floor (cracked floor too).
        self.placeable = bytearray(n)
        for c in range(n):
            if (self.blocks[c] or c in self.signs or c in self.spinners or c in self.bends
                    or c in self.switches or c in self.gates or c in self.portals
                    or c in self.dots or c == self.home or c in start_cells):
                continue
            self.placeable[c] = 1


class State:
    __slots__ = ("cells", "dirs", "status", "got", "nxt", "spin", "flip", "holes", "tick")

    def __init__(self, board=None):
        if board is None:
            return
        self.cells = [c for c, _ in board.starts]
        self.dirs = [d for _, d in board.starts]
        self.status = [0] * len(board.starts)  # 0 rolling, 1 home, 2 crashed
        self.got = 0
        self.nxt = 1
        self.spin = list(board.spin0)
        self.flip = 0
        self.holes = 0
        self.tick = 0

    def copy(self):
        s = State()
        s.cells = list(self.cells)
        s.dirs = list(self.dirs)
        s.status = list(self.status)
        s.got = self.got
        s.nxt = self.nxt
        s.spin = list(self.spin)
        s.flip = self.flip
        s.holes = self.holes
        s.tick = self.tick
        return s

    def key(self):
        return (tuple(self.cells), tuple(self.dirs), tuple(self.status), self.got, self.nxt,
                tuple(self.spin), self.flip, self.holes)


def tick(b, s, arrows, events=None):
    """Advances one tick. `arrows` maps cell -> direction (None = no arrow).
    Returns WIN, LOSE or GOING."""
    s.tick += 1
    w = b.w
    movers = [i for i in range(len(s.cells)) if s.status[i] == 0]
    for i in movers:
        k = b.cracks.get(s.cells[i])
        if k is not None and not (s.holes >> k) & 1:
            s.holes |= 1 << k
            if events is not None:
                events.append((s.tick, "crumble", i, s.cells[i]))
    targets = {}
    for i in movers:
        c = s.cells[i]
        x, y = c % w + DX[s.dirs[i]], c // w + DY[s.dirs[i]]
        if x < 0 or y < 0 or x >= w or y >= b.h:
            s.status[i] = 2
            if events is not None:
                events.append((s.tick, "edge", i, c))
            continue
        targets[i] = y * w + x
    if len(targets) > 1:
        ids = list(targets)
        for a in range(len(ids)):
            for bb in range(a + 1, len(ids)):
                i, j = ids[a], ids[bb]
                # Rolling into an open home together is fine; anywhere else it's a crash.
                together = targets[i] == targets[j] and not (targets[i] == b.home and s.got == b.all_dots)
                if together or (targets[i] == s.cells[j] and targets[j] == s.cells[i]):
                    for k in (i, j):
                        s.status[k] = 2
                    if events is not None:
                        events.append((s.tick, "collide", i, targets[i]))
        for i in list(targets):
            if s.status[i] == 2:
                del targets[i]
    for i in movers:
        if i not in targets:
            continue
        c = targets[i]
        blocked = b.blocks[c]
        if not blocked and c in b.gates:
            blocked = not (b.gates[c] ^ s.flip)
        if not blocked and c in b.cracks:
            blocked = (s.holes >> b.cracks[c]) & 1
        if blocked:
            s.status[i] = 2
            if events is not None:
                events.append((s.tick, "crash", i, c))
            continue
        s.cells[i] = c
        if c in b.portals:
            c = b.portals[c]
            s.cells[i] = c
            if events is not None:
                events.append((s.tick, "portal", i, c))
        dot = b.dots.get(c)
        if dot is not None and not (s.got >> dot[0]) & 1:
            if dot[1] == 0 or dot[1] == s.nxt:
                s.got |= 1 << dot[0]
                if dot[1]:
                    s.nxt += 1
                if events is not None:
                    events.append((s.tick, "dot", i, c))
        if c == b.home and s.got == b.all_dots:
            s.status[i] = 1
            if events is not None:
                events.append((s.tick, "home", i, c))
            continue
        a = arrows.get(c)
        if a is not None:
            if events is not None and a != s.dirs[i]:
                events.append((s.tick, "arrow", i, c))
            s.dirs[i] = a
        elif c in b.signs:
            if events is not None and b.signs[c] != s.dirs[i]:
                events.append((s.tick, "sign", i, c))
            s.dirs[i] = b.signs[c]
        elif c in b.spinners:
            k = b.spinners[c]
            s.dirs[i] = s.spin[k]
            s.spin[k] = (s.spin[k] + 1) % 4
            if events is not None:
                events.append((s.tick, "spinner", i, c))
        elif c in b.bends:
            s.dirs[i] = BEND[b.bends[c]][s.dirs[i]]
            if events is not None:
                events.append((s.tick, "bend", i, c))
        if c in b.switches:
            s.flip ^= 1
            if events is not None:
                events.append((s.tick, "switch", i, c))
    if 2 in s.status:
        return LOSE
    if all(st == 1 for st in s.status):
        return WIN
    return GOING


def play(lv, arrows, events=None, trace=None):
    """Runs a level with the player's arrows ({cell: dir}). Returns (result, state)."""
    b = Board(lv)
    s = State(b)
    seen = {s.key()}
    while True:
        r = tick(b, s, arrows, events)
        if trace is not None:
            trace.append(list(s.cells))
        if r != GOING:
            return r, s
        k = s.key()
        if k in seen or s.tick >= MAX_TICKS:
            if events is not None:
                events.append((s.tick, "loop", 0, s.cells[0]))
            return LOSE, s
        seen.add(k)


def arrows_of(lv, solution):
    w = lv["w"]
    return {y * w + x: d for x, y, d in solution}


# --- Solver --------------------------------------------------------------------

class Solver:
    """Finds every set of at most `budget` arrows that wins. An arrow is decided the
    first time an orb rolls onto a free cell (none, or one of four directions), so
    only cells the orb actually visits are ever tried."""

    def __init__(self, lv, budget, cap=40, node_cap=3_000_000):
        self.lv = lv
        self.b = Board(lv)
        self.budget = budget
        self.cap = cap
        self.node_cap = node_cap
        self.nodes = 0
        self.solutions = []
        self.seen = set()
        self.aborted = False

    def run(self):
        self._dfs(State(self.b), {}, 0)
        return self.solutions

    def _dfs(self, s, decided, used):
        b = self.b
        added = []
        try:
            while True:
                if len(self.solutions) >= self.cap or self.nodes > self.node_cap:
                    self.aborted = self.nodes > self.node_cap
                    return
                for i in range(len(s.cells)):
                    c = s.cells[i]
                    if s.status[i] == 0 and b.placeable[c] and c not in decided:
                        self.nodes += 1
                        options = [None]
                        if used < self.budget:
                            here = s.dirs[i]
                            # Turning arrows first, then the arrow that points straight on
                            # (it only matters if an orb comes back this way).
                            options += [d for d in range(4) if d != here] + [here]
                        for opt in options:
                            d2 = dict(decided)
                            d2[c] = opt
                            s2 = s.copy()
                            if opt is not None:
                                s2.dirs[i] = opt
                            self._dfs(s2, d2, used + (opt is not None))
                        return
                k = s.key()
                if k in self.seen:
                    return
                self.seen.add(k)
                added.append(k)
                r = tick(b, s, decided)
                if r == WIN:
                    w = b.w
                    sol = sorted((c % w, c // w, d) for c, d in decided.items() if d is not None)
                    self.solutions.append(sol)
                    return
                if r == LOSE or s.tick >= MAX_TICKS:
                    return
        finally:
            for k in added:
                self.seen.discard(k)


def solve(lv, max_budget=7, cap=40, node_cap=3_000_000):
    """Fewest arrows that win, every solution at that count (up to `cap`), and the
    search effort. Returns None if nothing wins within max_budget."""
    total = 0
    for budget in range(0, max_budget + 1):
        sv = Solver(lv, budget, cap, node_cap)
        sols = sv.run()
        total += sv.nodes
        if sv.aborted:
            return None
        if sols:
            return {"turns": budget, "solutions": sols, "nodes": sv.nodes, "total": total}
    return None


# --- Chapters ------------------------------------------------------------------

# Play order and each chapter's one new idea. Ids stay put if the order changes.
CHAPTERS = [
    {"id": "ch1", "name": "Path", "idea": None},
    {"id": "ch2", "name": "Signs", "idea": "signs"},
    {"id": "ch3", "name": "Bank", "idea": "bends"},
    {"id": "ch4", "name": "Gate", "idea": "gates"},
    {"id": "ch5", "name": "Spin", "idea": "spinners"},
    {"id": "ch6", "name": "Shift", "idea": "portals"},
    {"id": "ch7", "name": "Crumble", "idea": "cracks"},
    {"id": "ch8", "name": "Count", "idea": "ordered"},
    {"id": "ch9", "name": "Pair", "idea": "twin"},
]


def turn_goal(n):
    """Arrows the player gets on level n (1-based): 1 at the start of a chapter, 5 at 40."""
    return 1 + round((n - 1) * 4 / 39)


def dot_goal(n, rng):
    return max(1, min(6, 1 + (n + rng.randint(0, 6)) // 8))


def board_size(n, rng):
    if n <= 4:
        return rng.choice([(5, 6), (5, 7)])
    if n <= 12:
        return rng.choice([(5, 7), (6, 7), (6, 8)])
    if n <= 26:
        return rng.choice([(6, 8), (7, 8), (6, 9)])
    return rng.choice([(7, 8), (7, 9)])


# --- Generator -----------------------------------------------------------------

class Walk:
    """Builds a level by rolling an orb across an empty board and laying the level
    down under it: arrows where it turns, dots on its way, features of the chapter,
    and home where it stops. Blocks go in afterwards to rule out shortcuts."""

    def __init__(self, rng, w, h, turns, dots, feats, idea):
        self.rng = rng
        self.w, self.h = w, h
        self.turns = turns
        self.dots_goal = dots
        self.feats = feats
        self.idea = idea
        self.lv = {"w": w, "h": h, "blocks": [], "dots": [], "signs": [], "spinners": [],
                   "bends": [], "switches": [], "gates": [], "portals": [], "cracks": []}

    def build(self):
        rng = self.rng
        w, h = self.w, self.h
        for _ in range(60):
            lv = self._try()
            if lv is not None:
                return lv
        return None

    def _try(self):
        rng = self.rng
        w, h = self.w, self.h
        lv = json.loads(json.dumps(self.lv))
        used = {}  # cell -> kind
        sx, sy = rng.randrange(w), rng.randrange(h)
        sd = rng.randrange(4)
        # Point the start into the board with room to roll.
        room = [(sx - 0) if d == 2 else (w - 1 - sx) if d == 0 else (h - 1 - sy) if d == 1 else sy for d in range(4)]
        sd = max(range(4), key=lambda d: room[d] + rng.random() * 2)
        if room[sd] < 2:
            return None
        start = sy * w + sx
        used[start] = "start"
        arrows = {}
        path = []  # (cell, dir_out, tick)
        cell, d = start, sd
        visits = {start: 1}
        arrows_left = self.turns
        feat_turns = 0
        flip = 0
        spins = {}
        twin_idea = self.idea == "twin"
        steps = 0
        seg = 0
        max_steps = w * h * 2
        want_feat = self._feature_plan()
        while steps < max_steps:
            steps += 1
            x, y = cell % w + DX[d], cell // w + DY[d]
            if x < 0 or y < 0 or x >= w or y >= h:
                return None
            nxt = y * w + x
            kind = used.get(nxt)
            if kind in ("start", "home", "dot", "switch", "portal", "gate_closed", "crack"):
                # Don't run over things already laid down (keeps runs readable).
                if kind != "dot" or rng.random() < 0.7:
                    return None
            cell = nxt
            visits[cell] = visits.get(cell, 0) + 1
            seg += 1
            if kind == "arrow":
                d = arrows[cell]
                seg = 0
                path.append((cell, d))
                continue
            if kind == "sign":
                d = next(s[2] for s in lv["signs"] if s[1] * w + s[0] == cell)
                seg = 0
                path.append((cell, d))
                continue
            if kind == "bend":
                k = next(s[2] for s in lv["bends"] if s[1] * w + s[0] == cell)
                d = BEND[k][d]
                seg = 0
                path.append((cell, d))
                continue
            if kind == "spinner":
                d = spins[cell]
                spins[cell] = (d + 1) % 4
                seg = 0
                path.append((cell, d))
                continue
            if kind is not None and kind != "pass":
                return None
            fresh = kind is None
            # Ahead: how far the orb could roll straight on.
            ahead = 0
            ax, ay = x, y
            while True:
                ax, ay = ax + DX[d], ay + DY[d]
                if ax < 0 or ay < 0 or ax >= w or ay >= h:
                    break
                ahead += 1
            must_turn = ahead == 0
            want_turn = seg >= 1 and (must_turn or rng.random() < 0.2 + 0.11 * seg)
            if fresh and want_turn and (arrows_left > 0 or want_feat):
                turn = rng.choice([1, 3]) if rng.random() < 0.92 else 2
                nd = (d + turn) % 4
                feat = want_feat[0] if want_feat and rng.random() < 0.55 else None
                if feat in ("signs", "spinners") or (feat == "bends" and turn != 2):
                    want_feat.pop(0)
                    used[cell] = feat[:-1]
                    if feat == "signs":
                        lv["signs"].append([x, y, nd])
                    elif feat == "spinners":
                        lv["spinners"].append([x, y, nd])
                        spins[cell] = (nd + 1) % 4
                    else:
                        lv["bends"].append([x, y, 0 if BEND[0][d] == nd else 1])
                    feat_turns += 1
                elif arrows_left > 0:
                    arrows_left -= 1
                    used[cell] = "arrow"
                    arrows[cell] = nd
                else:
                    if must_turn:
                        return None
                    used[cell] = "pass"
                    path.append((cell, d))
                    continue
                d = nd
                seg = 0
                path.append((cell, d))
                continue
            if must_turn:
                return None
            if fresh:
                if want_feat and want_feat[0] == "portals" and seg >= 1 and rng.random() < 0.3:
                    # Jump: this cell and a far free cell become a portal pair.
                    far = [c for c in range(w * h) if c not in used and c != cell
                           and abs(c % w - x) + abs(c // w - y) >= 3]
                    rng.shuffle(far)
                    ok = None
                    for f in far:
                        fx, fy = f % w + DX[d], f // w + DY[d]
                        if 0 <= fx < w and 0 <= fy < h and (fy * w + fx) not in used:
                            ok = f
                            break
                    if ok is not None:
                        want_feat.pop(0)
                        used[cell] = "portal"
                        used[ok] = "portal"
                        lv["portals"].append([x, y, ok % w, ok // w])
                        cell = ok
                        path.append((cell, d))
                        continue
                if want_feat and want_feat[0] == "gates" and rng.random() < 0.35:
                    if not lv["switches"]:
                        want_feat.pop(0)
                        used[cell] = "switch"
                        lv["switches"].append([x, y])
                        flip ^= 1
                        path.append((cell, d))
                        continue
                if "gates" in self.feats and lv["switches"] and flip and rng.random() < 0.3 and len(lv["gates"]) < 3:
                    used[cell] = "gate_closed"
                    lv["gates"].append([x, y, 0])
                    path.append((cell, d))
                    continue
                if want_feat and want_feat[0] == "cracks" and rng.random() < 0.6:
                    used[cell] = "crack"
                    lv["cracks"].append([x, y])
                    if len(lv["cracks"]) >= 3:
                        want_feat.pop(0)
                    path.append((cell, d))
                    continue
                used[cell] = "pass"
            path.append((cell, d))
            done = arrows_left == 0 and not want_feat and seg >= 1
            if done and rng.random() < 0.5:
                break
        else:
            return None
        if arrows_left > 0 or want_feat:
            return None
        # Home where the orb stopped, if that cell is plain and visited once.
        if visits.get(cell, 0) != 1 or used.get(cell) != "pass":
            return None
        used[cell] = "home"
        lv["home"] = [cell % w, cell // w]
        # Dots on plain cells the orb rolled over, spread along the run.
        plain = []
        seen_c = set()
        for c, _ in path:
            if used.get(c) == "pass" and c not in seen_c and visits[c] == 1:
                plain.append(c)
                seen_c.add(c)
        if len(plain) < self.dots_goal:
            return None
        picks = sorted(rng.sample(range(len(plain)), self.dots_goal))
        ordered = self.idea == "ordered" or ("ordered" in self.feats and rng.random() < 0.5)
        for n, p in enumerate(picks):
            c = plain[p]
            used[c] = "dot"
            lv["dots"].append([c % w, c // w, n + 1] if ordered else [c % w, c // w])
        lv["starts"] = [[sx, sy, sd]]
        lv["_arrows"] = [[c % w, c // w, a] for c, a in arrows.items()]
        if twin_idea and not self._add_twin(lv, used, arrows, path):
            return None
        lv["_used"] = {str(k): v for k, v in used.items()}
        return lv

    def _feature_plan(self):
        rng = self.rng
        plan = []
        for f in self.feats:
            if f == "signs":
                plan += ["signs"] * rng.randint(1, 2)
            elif f == "bends":
                plan += ["bends"] * rng.randint(1, 3)
            elif f == "spinners":
                plan += ["spinners"] * rng.randint(1, 2)
            elif f in ("portals", "gates", "cracks"):
                plan.append(f)
        rng.shuffle(plan)
        return plan

    def _add_twin(self, lv, used, arrows, path):
        """A second orb that rolls into one of the run's arrows from the side and then
        follows the first orb home, a few ticks behind it."""
        rng = self.rng
        w, h = self.w, self.h
        times = {}
        for t, (c, _) in enumerate(path, start=1):
            times.setdefault(c, t)
        options = []
        for c, a in arrows.items():
            for d in range(4):
                if d == a:
                    continue
                # Walk back from c against direction d to find a start.
                x, y = c % w, c // w
                for dist in range(1, max(w, h)):
                    x, y = x - DX[d], y - DY[d]
                    if x < 0 or y < 0 or x >= w or y >= h:
                        break
                    cc = y * w + x
                    if cc in used:
                        break
                    if dist >= 2 and dist > times.get(c, 0):
                        options.append((cc, d, dist))
        if not options:
            return False
        cc, d, dist = rng.choice(options)
        used[cc] = "start"
        lv["starts"].append([cc % w, cc // w, d])
        return True


def add_blocks(lv, rng, density):
    """Blocks on cells the intended run never touches."""
    w, h = lv["w"], lv["h"]
    used = {int(k) for k in lv["_used"]}
    free = [c for c in range(w * h) if c not in used]
    rng.shuffle(free)
    n = int(len(free) * density)
    for c in free[:n]:
        lv["blocks"].append([c % w, c // w])


def add_decoys(lv, rng, feats):
    w, h = lv["w"], lv["h"]
    used = {int(k) for k in lv["_used"]} | {b[1] * w + b[0] for b in lv["blocks"]}
    free = [c for c in range(w * h) if c not in used]
    rng.shuffle(free)

    def take():
        c = free.pop()
        lv["_used"][str(c)] = "decoy"
        return c % w, c // w

    if "signs" in feats and free and rng.random() < 0.7:
        x, y = take()
        lv["signs"].append([x, y, rng.randrange(4)])
    if "bends" in feats and free and rng.random() < 0.7:
        x, y = take()
        lv["bends"].append([x, y, rng.randrange(2)])
    if "spinners" in feats and free and rng.random() < 0.4:
        x, y = take()
        lv["spinners"].append([x, y, rng.randrange(4)])
    if "gates" in feats and lv["switches"] and free and rng.random() < 0.7:
        # An open gate that the switch will close behind you.
        x, y = take()
        lv["gates"].append([x, y, 1])
    if "cracks" in feats and free:
        for _ in range(rng.randint(1, 3)):
            if free:
                x, y = take()
                lv["cracks"].append([x, y])


def run_cells(lv, solution):
    """Every cell the winning run touches."""
    trace = []
    play(lv, arrows_of(lv, solution), trace=trace)
    cells = {c for c, _ in Board(lv).starts}
    for t in trace:
        cells.update(t)
    return cells


def tighten(lv, rng, goal, max_blocks):
    """Blocks shortcuts: while a cheaper or a different solution exists, put a block
    on a cell only that solution uses. Returns the final solve result (or None)."""
    w = lv["w"]
    intended = run_cells(lv, lv["_arrows"])
    for _ in range(14):
        res = solve(lv, max_budget=goal, cap=12, node_cap=600_000)
        if res is None:
            return None
        if res["turns"] == goal and len(res["solutions"]) <= 2:
            return res
        if len(lv["blocks"]) >= max_blocks:
            return res
        # Pick an unwanted solution and block a cell only it visits.
        others = [s for s in res["solutions"] if sorted(map(tuple, s)) != sorted(map(tuple, lv["_arrows"]))]
        if not others:
            return res
        sol = rng.choice(others[:4])
        cells = run_cells(lv, sol) - intended
        b = Board(lv)
        cells = [c for c in cells if b.placeable[c] and c not in b.cracks]
        if not cells:
            return res
        c = rng.choice(cells)
        lv["blocks"].append([c % w, c // w])
    return solve(lv, max_budget=goal, cap=12, node_cap=600_000)


def features_used(lv, solution):
    """Which ideas the winning run actually uses."""
    ev = []
    play(lv, arrows_of(lv, solution), events=ev)
    kinds = {e[1] for e in ev}
    out = set()
    if "sign" in kinds:
        out.add("signs")
    if "bend" in kinds:
        out.add("bends")
    if "spinner" in kinds:
        out.add("spinners")
    if "portal" in kinds:
        out.add("portals")
    gate_cells = {g[1] * lv["w"] + g[0] for g in lv.get("gates", [])}
    if "switch" in kinds and gate_cells & run_cells(lv, solution):
        out.add("gates")
    if "crumble" in kinds and lv.get("cracks"):
        out.add("cracks")
    if any(len(d) > 2 for d in lv["dots"]) and len(lv["dots"]) >= 2:
        out.add("ordered")
    if len(lv["starts"]) > 1:
        out.add("twin")
    return out, ev


def signature(lv, solution):
    """Shape of the winning run: the sequence of turns (L, R, B) and what made them."""
    ev = []
    trace = []
    play(lv, arrows_of(lv, solution), events=ev, trace=trace)
    sig = ""
    for e in ev:
        if e[1] in ("arrow", "sign", "spinner", "bend"):
            sig += e[1][0].upper()
    return sig + "|%dx%d|%d" % (lv["w"], lv["h"], len(lv["dots"]))


def make_candidate(args):
    chapter, n, seed = args
    rng = random.Random(seed)
    idea = chapter["idea"]
    order = [c["idea"] for c in CHAPTERS]
    earlier = [f for f in order[1:order.index(idea)]] if idea else []
    feats = [idea] if idea and idea not in ("ordered", "twin") else []
    if idea in ("ordered", "twin"):
        feats.append(idea)
    # From about level 16, mix in one earlier idea now and then.
    if n >= 16 and earlier and rng.random() < 0.55:
        extra = rng.choice([f for f in earlier if f not in ("twin",)])
        if extra not in feats:
            feats.append(extra)
    goal = turn_goal(n)
    w, h = board_size(n, rng)
    dots = dot_goal(n, rng)
    walk = Walk(rng, w, h, goal, dots, [f for f in feats if f not in ("ordered", "twin")], idea)
    walk.feats = feats
    lv = walk.build()
    if lv is None:
        return None
    add_decoys(lv, rng, feats)
    add_blocks(lv, rng, rng.uniform(0.08, 0.22))
    # The intended run must still win (decoys and blocks sit off it).
    r, _ = play(lv, arrows_of(lv, lv["_arrows"]))
    if r != WIN:
        return None
    max_blocks = int(w * h * 0.3)
    res = tighten(lv, rng, goal, max_blocks)
    if res is None or res["turns"] != goal:
        return None
    sol = res["solutions"][0]
    used, ev = features_used(lv, sol)
    if idea and idea not in used:
        return None
    ticks = max(e[0] for e in ev)
    out = {k: v for k, v in lv.items() if not k.startswith("_") and v != []}
    out["turns"] = goal
    out["solution"] = [list(s) for s in sol]
    out["solutions"] = len(res["solutions"])
    out["ticks"] = ticks
    out["nodes"] = res["total"]
    out["sig"] = signature(lv, sol)
    out["uses"] = sorted(used)
    # Effort: a bigger search and a more unique answer read as harder.
    out["effort"] = round(math.log10(1 + res["total"]) + 0.15 * len(lv["dots"]) + 0.02 * ticks
                          - 0.35 * math.log2(len(res["solutions"])), 4)
    return out


# Hand-made opening rooms: each shows its chapter's idea as plainly as possible.
# (The others are the generator's gentlest room.) The solver still checks them.
INTROS = {
    # A sign turns the orb up; you add the turn into home.
    "ch2": {"w": 5, "h": 7, "starts": [[0, 6, 0]], "signs": [[2, 6, 3]], "dots": [[2, 4]], "home": [4, 2]},
    # A bend banks the orb up; the second bend is where it goes if you do nothing.
    "ch3": {"w": 5, "h": 7, "starts": [[0, 5, 0]], "bends": [[2, 5, 0], [2, 1, 1]], "dots": [[1, 5]], "home": [4, 3]},
    # The spinner sends the orb up, then turns: on the way back it sends it right.
    "ch5": {"w": 5, "h": 7, "starts": [[0, 3, 0]], "spinners": [[2, 3, 3]], "dots": [[2, 1]], "home": [4, 3]},
    # In one portal, out the other, still heading up.
    "ch6": {"w": 5, "h": 7, "starts": [[0, 6, 3]], "portals": [[0, 3, 4, 5]], "dots": [[0, 4]], "home": [2, 2]},
    # Dot 2 comes first but only counts after dot 1; home opens after both.
    "ch8": {"w": 5, "h": 7, "starts": [[2, 0, 1]], "dots": [[2, 2, 2], [2, 4, 1]], "home": [2, 1], "blocks": [[2, 6]]},
}


def finish_intro(cid):
    lv = json.loads(json.dumps(INTROS[cid]))
    res = solve(lv, max_budget=2, cap=8)
    if res is None or res["turns"] != 1 or len(res["solutions"]) != 1:
        raise SystemExit("%s: the opening room should need exactly one arrow, one way (%s)" % (cid, res))
    sol = res["solutions"][0]
    used, ev = features_used(lv, sol)
    out = dict(lv)
    out["turns"] = 1
    out["solution"] = [list(x) for x in sol]
    out["solutions"] = 1
    out["ticks"] = max(e[0] for e in ev)
    out["nodes"] = res["total"]
    out["sig"] = signature(lv, sol)
    out["uses"] = sorted(used)
    out["effort"] = 0.0
    return out


def build_chapter(ch, seed_base, pool):
    print("%s %s" % (ch["id"], ch["name"]), flush=True)
    levels = []
    by_goal = {}
    for n in range(1, LEVELS_PER_CHAPTER + 1):
        by_goal.setdefault(turn_goal(n), []).append(n)
    picked = {}
    for goal, slots in sorted(by_goal.items()):
        want = len(slots) * 9 + 12
        cands = []
        seed = seed_base + goal * 100000
        tries = 0
        while len(cands) < want and tries < 40:
            tries += 1
            jobs = [(ch, slots[min(len(slots) - 1, (i % len(slots)))], seed + i) for i in range(160)]
            seed += 160
            for c in pool.imap_unordered(make_candidate, jobs, chunksize=4):
                if c is not None and c["solutions"] <= 3:
                    cands.append(c)
            print("  %d turns: %d candidates" % (goal, len(cands)), flush=True)
        # Unique answers first, then by effort; spread picks over the upper range.
        cands.sort(key=lambda c: c["effort"])
        unique = {}
        for c in cands:
            unique.setdefault(json.dumps({k: c[k] for k in ("w", "h", "starts", "home")}), c)
        cands = sorted(unique.values(), key=lambda c: c["effort"])
        m = len(cands)
        if m < len(slots):
            raise SystemExit("%s: only %d candidates for %d-turn levels" % (ch["id"], m, goal))
        lo = 0 if slots[0] == 1 else int(m * 0.15)
        k = len(slots)
        # Evenly spread over the upper range, so effort rises level by level; a pick
        # that repeats its neighbour's shape slides up to the next candidate.
        marks = [lo + int(round(j * (m - 1 - lo) / max(1, k - 1))) for j in range(k)]
        if slots[0] == 1:
            marks[0] = 0
        chosen = []
        prev_sig = picked[slots[0] - 1]["sig"] if slots[0] > 1 else None
        for j, mark in enumerate(marks):
            limit = marks[j + 1] if j + 1 < k else m
            i = max(mark, (cands.index(chosen[-1]) + 1) if chosen else mark)
            while i < limit - 1 and cands[i]["sig"] == prev_sig:
                i += 1
            if cands[i]["sig"] == prev_sig:
                # No room above: look back down, still above the previous pick.
                floor = cands.index(chosen[-1]) + 1 if chosen else 0
                for i2 in range(i - 1, floor - 1, -1):
                    if cands[i2]["sig"] != prev_sig:
                        i = i2
                        break
            if i >= m:
                raise SystemExit("%s: ran out of candidates at level %d" % (ch["id"], slots[j]))
            chosen.append(cands[i])
            prev_sig = cands[i]["sig"]
        for n, c in zip(slots, chosen):
            picked[n] = c
    if ch["id"] in INTROS:
        picked[1] = finish_intro(ch["id"])
    for n in range(1, LEVELS_PER_CHAPTER + 1):
        lv = dict(picked[n])
        lv["id"] = "%s_%02d" % (ch["id"], n)
        lv["number"] = n
        lv["difficulty"] = round(lv["turns"] + min(0.999, max(0.0, lv["effort"] / 12.0)), 4)
        if n == 1:
            lv["intro"] = True
        levels.append(lv)
    # Strictly rising difficulty inside each turn count (level 1 aside).
    for i in range(2, len(levels)):
        if levels[i]["difficulty"] <= levels[i - 1]["difficulty"]:
            levels[i]["difficulty"] = round(levels[i - 1]["difficulty"] + 0.0001, 4)
    return {"id": ch["id"], "name": ch["name"], "levels": levels}


def write_chapter(data):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, data["id"] + ".json")
    with open(path, "w") as f:
        f.write("{\"id\":%s,\"name\":%s,\"levels\":[\n" % (json.dumps(data["id"]), json.dumps(data["name"])))
        f.write(",\n".join(json.dumps(lv, separators=(",", ":")) for lv in data["levels"]))
        f.write("\n]}\n")
    print("wrote", os.path.relpath(path, ROOT), flush=True)


def check_all():
    bad = 0
    for ch in CHAPTERS:
        data = json.load(open(os.path.join(OUT_DIR, ch["id"] + ".json")))
        for lv in data["levels"]:
            r, _ = play(lv, arrows_of(lv, lv["solution"]))
            res = solve(lv, max_budget=lv["turns"], cap=12)
            if r != WIN or res is None or res["turns"] != lv["turns"]:
                print("BAD", lv["id"])
                bad += 1
    print("checked, %d bad" % bad)


def main(argv):
    if "--check" in argv:
        check_all()
        return
    want = [a for a in argv if a.startswith("ch")]
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        for i, ch in enumerate(CHAPTERS):
            if want and ch["id"] not in want:
                continue
            write_chapter(build_chapter(ch, 1000003 * (i + 1), pool))


if __name__ == "__main__":
    main(sys.argv[1:])
