#!/usr/bin/env python3
"""Regenerates the workflow diagrams (SVG) in this folder. PNGs are exported with: scripts/diagrams."""
import html
import os

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "Inter, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
INK, MUTED, LINE = "#1f2328", "#57606a", "#8c959f"
KIND = {  # fill, stroke
    "you": ("#ddf4ff", "#0969da"),
    "main": ("#fff8c5", "#9a6700"),
    "agent": ("#dafbe1", "#1a7f37"),
    "script": ("#fbefff", "#8250df"),
    "state": ("#eaeef2", "#57606a"),
    "stop": ("#ffebe9", "#cf222e"),
}


class Svg:
    def __init__(self, w, h, title, subtitle=""):
        self.w, self.h, self.parts = w, h, []
        self.parts.append(f'<rect width="{w}" height="{h}" fill="#ffffff"/>')
        self.text(40, 52, title, size=26, weight=700)
        if subtitle:
            self.text(40, 80, subtitle, size=15, fill=MUTED)

    def text(self, x, y, s, size=14, weight=400, fill=INK, anchor="start"):
        self.parts.append(
            f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}">{html.escape(s)}</text>')

    def box(self, x, y, w, h, lines, kind="state", badge=None, sub=None, dashed=False):
        fill, stroke = KIND[kind]
        dash = ' stroke-dasharray="6 4"' if dashed else ""
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{stroke}" stroke-width="1.6"{dash}/>')
        if isinstance(lines, str):
            lines = [lines]
        total = len(lines) + (1 if sub else 0)
        top = y + h / 2 - (total - 1) * 9 + 5
        for i, ln in enumerate(lines):
            self.text(x + w / 2, top + i * 18, ln, size=14, weight=600 if i == 0 else 400, anchor="middle")
        if sub:
            self.text(x + w / 2, top + len(lines) * 18, sub, size=12, fill=MUTED, anchor="middle")
        if badge:
            r = 13
            self.parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{stroke}"/>')
            self.text(x, y + 5, str(badge), size=13, weight=700, fill="#ffffff", anchor="middle")

    def tag(self, x, y, s, kind="stop"):
        fill, stroke = KIND[kind]
        w = 8 + 7.2 * len(s)
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="22" rx="11" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')
        self.text(x + w / 2, y + 15, s, size=12, weight=700, fill=stroke, anchor="middle")

    def arrow(self, x1, y1, x2, y2, label=None, dashed=False, color=LINE, lx=0, ly=-6, curve=0):
        dash = ' stroke-dasharray="6 4"' if dashed else ""
        if curve:
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2 + curve
            d = f"M{x1},{y1} Q{mx},{my} {x2},{y2}"
        else:
            d = f"M{x1},{y1} L{x2},{y2}"
        self.parts.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.8"{dash} marker-end="url(#a)"/>')
        if label:
            mx, my = (x1 + x2) / 2 + lx, (y1 + y2) / 2 + ly + (curve / 2 if curve else 0)
            self.text(mx, my, label, size=12, fill=MUTED, anchor="middle")

    def elbow(self, x1, y1, x2, y2, drop=34):
        """Down from (x1,y1), left/right along a gutter, down into (x2,y2): for wrapping to the next row."""
        d = f"M{x1},{y1} L{x1},{y1 + drop} L{x2},{y1 + drop} L{x2},{y2}"
        self.parts.append(f'<path d="{d}" fill="none" stroke="{LINE}" stroke-width="1.8" marker-end="url(#a)"/>')

    def legend(self, x, y, items):
        for i, (kind, s) in enumerate(items):
            fill, stroke = KIND[kind]
            cx = x + i * 190
            self.parts.append(f'<rect x="{cx}" y="{y}" width="18" height="18" rx="5" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>')
            self.text(cx + 26, y + 14, s, size=13, fill=MUTED)

    def save(self, name):
        defs = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">'
                f'<path d="M0,0 L10,5 L0,10 z" fill="{LINE}"/></marker></defs>')
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">'
               + defs + "".join(self.parts) + "</svg>\n")
        with open(os.path.join(OUT, name), "w") as f:
            f.write(svg)


def workflow():
    s = Svg(1200, 800, "How a goal flows through the team",
            "A standard user-facing goal. You are asked at the three red markers; everything else runs on its own.")
    cols = [40 + 228 * i for i in range(5)]
    rows = [120, 330, 540]
    W, H = 210, 120
    steps = [
        ("you", ["You describe", "a goal"], "plain words or /devteam:goal", None),
        ("main", ["Intake", "Product Owner + Architect"], "questions, recommended answers", "stop"),
        ("main", ["One confirmation", "contract, lane, lifecycle,", "git permissions"], "plus the quality criterion", "stop"),
        ("agent", ["Research", "Research Analyst"], "verified versions, cited", None),
        ("agent", ["Acceptance tests", "QA Engineer"], "written first, hash-locked", None),
        ("agent", ["Architecture", "Software Architect"], "design.md + ADRs, no waiting", None),
        ("agent", ["Design spec (UI)", "UX Designer"], "tokens, layout, real content", None),
        ("agent", ["Build", "Full-Stack Engineer"], "one task at a time, self-review", None),
        ("agent", ["Verify", "QA Engineer"], "gates + shots at 390/768/1280", None),
        ("agent", ["Quality loop", "UX Designer critiques"], "under 4/5? polish, max 2 rounds", None),
        ("agent", ["Review", "Staff Engineer"], "code and product quality", None),
        ("script", ["Verify done", "dt verify + Verifier"], "scripts decide, rubric on shots", None),
        ("main", ["Close-out", "PM asks once"], "manual criteria, commit, PR", "stop"),
        ("script", ["Close gate", "dt close"], "full suite on the final tree", None),
        ("state", ["Idle", "nothing running"], "next message = new goal", None),
    ]
    pos = []
    for i, (kind, lines, sub, stop) in enumerate(steps):
        r, c = divmod(i, 5)
        x, y = cols[c], rows[r]
        pos.append((x, y))
        s.box(x, y, W, H, lines, kind, badge=i + 1, sub=sub)
        if stop:
            s.tag(x + W - 92, y - 11, "YOU DECIDE", "stop")
    for i in range(len(steps) - 1):
        (x1, y1), (x2, y2) = pos[i], pos[i + 1]
        if y1 == y2:
            s.arrow(x1 + W + 2, y1 + H / 2, x2 - 2, y2 + H / 2)
        else:  # wrap to the next row, below-left
            s.elbow(x1 + W / 2, y1 + H + 2, x2 + W / 2, y2 - 2)
    s.legend(40, 740, [("you", "You"), ("main", "Your session (skills)"), ("agent", "Spawned agent"),
                       ("script", "Deterministic script"), ("state", "State")])
    s.save("workflow.svg")


def wrap(text, width=44):
    import textwrap
    return textwrap.wrap(text, width)


def states():
    s = Svg(1200, 580, "The life of a goal", "One goal at a time. Every transition is made by the dt script, and only dt closes a goal.")
    y, H = 200, 64
    box = {"ONBOARDING": (40, 130, "state"), "IDLE": (230, 130, "state"), "INTAKE": (420, 130, "main"),
           "ACTIVE": (610, 170, "agent"), "VERIFYING": (860, 140, "script"), "ACHIEVED": (1050, 130, "agent")}
    for k, (x, w, kind) in box.items():
        s.box(x, y, w, H, k, kind)
    mid = y + H / 2
    def fwd(a, b, label):
        xa, wa, _ = box[a]
        xb, _, _ = box[b]
        s.arrow(xa + wa + 2, mid, xb - 2, mid)
        s.text((xa + wa + xb) / 2, mid - 8, label, size=11, fill=MUTED, anchor="middle")
    fwd("ONBOARDING", "IDLE", "start")
    fwd("IDLE", "INTAKE", "goal")
    fwd("INTAKE", "ACTIVE", "confirm")
    fwd("ACTIVE", "VERIFYING", "done")
    fwd("VERIFYING", "ACHIEVED", "close")
    # closed: back to IDLE above the row
    s.elbow(1115, y - 2, 295, y - 2, drop=-62)
    s.text(705, y - 78, "closed: nothing keeps running, the next message starts a new goal", size=12, fill=MUTED, anchor="middle")
    # criteria fail: ACTIVE <- VERIFYING, a short loop above the row
    s.parts.append(f'<path d="M900,{y - 2} Q830,{y - 52} 765,{y - 2}" fill="none" stroke="{LINE}" stroke-width="1.8" marker-end="url(#a)"/>')
    s.text(830, y - 44, "criteria fail (max 2 returns)", size=11, fill=MUTED, anchor="middle")
    # PAUSED and BLOCKED hang below ACTIVE, each with a way out and a way back
    s.box(500, 380, 140, 64, "PAUSED", "state")
    s.box(760, 380, 150, 64, "BLOCKED", "stop", sub="waiting on you")
    s.arrow(650, y + H + 2, 600, 378)
    s.arrow(625, 378, 685, y + H + 2)
    s.text(552, 322, "you pause", size=11, fill=MUTED, anchor="end")
    s.text(672, 322, "resume", size=11, fill=MUTED, anchor="start")
    s.arrow(740, y + H + 2, 800, 378)
    s.arrow(830, 378, 770, y + H + 2)
    s.text(832, 300, "stall, cap, tamper,", size=11, fill=MUTED, anchor="start")
    s.text(832, 315, "failing gates", size=11, fill=MUTED, anchor="start")
    s.text(850, 362, "you resolve", size=11, fill=MUTED, anchor="start")
    # STOPPED: reachable from every state
    s.box(230, 380, 130, 64, "STOPPED", "state")
    s.arrow(295, 378, 295, y + H + 2, "cleaned up, team stood down", dashed=True, lx=-84, ly=0)
    s.text(295, 470, "/devteam:stop works from any state", size=12, fill=MUTED, anchor="middle")
    s.text(40, 540, "Gates never block you; they stop a goal from closing. Hooks are a second line of defence; the close gate has the last word.", size=13, fill=MUTED)
    s.save("states.svg")


def architecture():
    s = Svg(1200, 820, "Who does what", "Interactive roles run in your session; isolated roles are spawned agents that see only a short brief.")
    s.box(40, 130, 210, 110, ["You", "highest authority"], "you", sub="amend, pause, stop, models")
    s.box(350, 110, 330, 330, ["Your Claude Code session"], "main")
    s.text(515, 150, "skills run here, on your model", size=12, fill=MUTED, anchor="middle")
    s.box(370, 170, 290, 70, ["Goal Keeper (Product Owner)", "intake, criteria, confirmation"], "main")
    s.box(370, 255, 290, 70, ["PM (Project Manager)", "plans, spawns, briefs"], "main")
    s.box(370, 340, 290, 80, ["dt CLI", "state, criteria, gates, close"], "script", sub="the only thing that can close a goal")
    s.arrow(252, 170, 348, 170, None)
    s.text(300, 160, "goal, answers", size=11, fill=MUTED, anchor="middle")
    s.arrow(348, 205, 252, 205, None)
    s.text(300, 222, "questions", size=11, fill=MUTED, anchor="middle")
    agents = [("Research Analyst", "current versions, cited"), ("Software Architect", "design.md, ADRs"),
              ("UX Designer", "spec and critique"), ("QA Engineer", "tests and screenshots"),
              ("Full-Stack Engineer", "builds one task"), ("Staff Engineer", "review, read-only"),
              ("Acceptance Verifier", "judges from evidence")]
    s.text(970, 104, "spawned agents: fresh context, brief in, 150-word reply out", size=12, fill=MUTED, anchor="middle")
    for i, (n, d) in enumerate(agents):
        s.box(780, 116 + i * 58, 380, 50, [n], "agent", sub=d)
    s.arrow(682, 290, 778, 290, None)
    s.text(730, 280, "brief", size=11, fill=MUTED, anchor="middle")
    s.arrow(778, 318, 682, 318, None)
    s.text(730, 335, "reply", size=11, fill=MUTED, anchor="middle")
    s.box(40, 580, 1120, 76, ["Hooks (run on every tool call; near-instant when the team is not engaged)"], "script",
          sub="spawn guard  |  state and locked-test protection  |  tiered git guard  |  finish gate with retries  |  ledger")
    s.arrow(515, 442, 515, 578, "enforced by", dashed=True, lx=48, ly=0)
    s.arrow(970, 526, 970, 578, None, dashed=True)
    s.box(40, 700, 550, 80, ["Project files  .devteam/"], "state",
          sub="goal.md, criteria.json, design.md, design-spec.md, reference.md, board, evidence/shots")
    s.box(610, 700, 550, 80, ["Your git repository"], "state",
          sub="integration branch devteam/<goal>; your branch is restored and verified at close")
    s.save("architecture.svg")


def safety():
    s = Svg(1200, 600, "What the team may touch in git", "Prompt first, then only the roles that need it. Hooks enforce it; native permission rules back it up.")
    cols = [("Read", "open to every role, no prompt", "status, diff, log, show, blame", "agent",
             "Any role that needs to look may look."),
            ("Local write", "needs your per-goal grant", "branches, worktrees, commits, merges, restore your branch", "main",
             "Only engineers and QA write, and only on devteam/* or worktree branches. Never on your own branch."),
            ("Remote and destructive", "a prompt every time, exact command shown", "push, PR, deploy, reset\u00a0--hard, clean, branch\u00a0-D, force", "stop",
             "Agents cannot do these at all. The PM asks you with the exact command; a grant never covers them.")]
    for i, (t, who, what, kind, note) in enumerate(cols):
        x = 40 + i * 380
        s.box(x, 120, 350, 90, [t, who], kind)
        s.box(x, 235, 350, 100, ["Includes"] + wrap(what, 46), "state")
        s.box(x, 360, 350, 110, ["Rule"] + wrap(note, 46), "state")
    s.box(40, 500, 1120, 60, ["The tiny lane asks for no git permissions at all: changes stay uncommitted in your tree until you approve a commit."], "you")
    s.save("safety.svg")


if __name__ == "__main__":
    workflow()
    states()
    architecture()
    safety()
    print("wrote", ", ".join(sorted(f for f in os.listdir(OUT) if f.endswith(".svg"))))
