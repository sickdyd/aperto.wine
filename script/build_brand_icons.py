#!/usr/bin/env python3
"""Re-derive the aperto.wine app icon set from the wordmark's own letterforms.

The mark is not drawn by hand and is not meant to be hand-edited. It is the
lowercase `a` of "aperto" pulled straight out of EB Garamond at the weight and
tracking the `.wordmark` rule in `app/assets/tailwind/application.css` already
uses (600, -0.012em), set in core oxblood over a heavy section rule in deepest
oxblood, on paper. So the icon is the masthead compressed into a square rather
than a second, unrelated piece of art, and re-running this after a palette or
face change keeps it that way.

Zero border radius, no shadow, no gradient, no ground but paper — PRODUCT.md.

The face comes out of `@expo-google-fonts/eb-garamond`, which the Expo client
already depends on and renders with — so the icon is cut from the same metal as
the running app, and `mobile/package-lock.json` pins it. Nothing is downloaded
and nothing is vendored: the outlines are baked into the output, so nothing at
runtime needs the font either.

Usage (needs ImageMagick and librsvg on PATH, and `npm install` in `mobile/`):

    python3 -m venv /tmp/icons && /tmp/icons/bin/pip install fonttools
    /tmp/icons/bin/python script/build_brand_icons.py

Writes into `mobile/assets/images/` and `public/`.
"""

from __future__ import annotations

import math
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.basePen import NullPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

# The static 600 instance, which is the weight `.wordmark` sets. Picking the
# file by name rather than instancing a variable font keeps this pinned to
# whatever the lockfile resolved for the app itself.
FONT_RELATIVE = Path(
    "mobile/node_modules/@expo-google-fonts/eb-garamond/600SemiBold/EBGaramond_600SemiBold.ttf"
)
WORDMARK_TRACKING = -0.012  # .wordmark letter-spacing, in em

# The ledger palette, straight off the CSS custom properties.
PAPER = "#F6F2E9"  # --color-paper
OX1 = "#4A1219"    # --color-ox-1, also --color-rule-heavy
OX2 = "#6E1F2A"    # --color-ox-2, the wordmark's own oxblood
OX3 = "#8E2A36"    # --color-ox-3, the quieter tone `.wine` carries

# Proportions of the mark, all expressed against the letter height, so every
# size below is the same drawing at a different scale.
RULE_W_F = 1.40   # the rule overhangs the letter on both sides
RULE_T_F = 0.078  # heavy rule: 3px under a 28px wordmark, held at scale
GAP_F = 0.200     # letter baseline down to the rule
# The same two, for the wider lockup, against the lockup's own height.
LOCKUP_RULE_T_F = 0.075
LOCKUP_GAP_F = 0.300

# Android masks an adaptive icon's outer 18dp of 108dp on every side, and the
# shapes it masks to all fit inside the circle inscribed in the inner 72dp. Art
# that fits that circle survives circle, squircle and rounded-square alike.
ADAPTIVE_SAFE = 72 / 108
# A `purpose: "maskable"` PWA icon is cropped to a circle of 80% the width.
MASKABLE_SAFE = 0.8

REQUIRED_TOOLS = {"magick": "imagemagick", "rsvg-convert": "librsvg"}


class Wordmark:
    """The wordmark's glyph outlines, as SVG path data in font units.

    Coordinates come out y-down with the baseline at y=0, which is the space the
    SVGs below are laid out in.
    """

    def __init__(self, ttf: Path) -> None:
        font = TTFont(ttf)
        self.glyphs = font.getGlyphSet()
        self.upm = font["head"].unitsPerEm
        self.cmap = font.getBestCmap()
        # One inter-glyph step, in font units. Everything that positions a run
        # relative to another run has to use this and not a baked-in number,
        # or the two drift apart the moment the tracking or the UPM changes.
        self.track = WORDMARK_TRACKING * self.upm

    def _walk(self, text: str, pen_for):
        x = 0.0
        for ch in text:
            glyph = self.glyphs[self.cmap[ord(ch)]]
            glyph.draw(TransformPen(pen_for(), Transform(1, 0, 0, -1, x, 0)))
            x += glyph.width + self.track
        return x - self.track  # no tracking hangs off the final glyph

    def path(self, text: str) -> str:
        pens: list[SVGPathPen] = []

        def pen_for():
            pens.append(SVGPathPen(self.glyphs, ntos=lambda v: f"{v:.1f}"))
            return pens[-1]

        self._walk(text, pen_for)
        return " ".join(p.getCommands() for p in pens if p.getCommands())

    def advance(self, text: str) -> float:
        return self._walk(text, NullPen)

    def bounds(self, text: str) -> tuple[float, float, float, float]:
        pen = BoundsPen(self.glyphs)
        self._walk(text, lambda: pen)
        if pen.bounds is None:
            raise ValueError(f"{text!r} drew nothing")
        return pen.bounds


def mark(wm: Wordmark, size: int, letter_frac: float, letter: str, rule: str, ground: str | None = None) -> str:
    """One square artboard carrying the `a` over its rule, centred as a block.

    The letter and the rule are centred *together*, not the letter alone —
    otherwise the rule hangs off the bottom and the composition sits low.
    """
    d = wm.path("a")
    x0, y0, x1, y1 = wm.bounds("a")
    glyph_w, glyph_h = x1 - x0, y1 - y0

    letter_h = size * letter_frac
    scale = letter_h / glyph_h
    letter_w = glyph_w * scale
    rule_w = letter_w * RULE_W_F
    rule_t = letter_h * RULE_T_F
    gap = letter_h * GAP_F

    top = (size - (letter_h + gap + rule_t)) / 2
    cx = size / 2
    tx = cx - letter_w / 2 - x0 * scale
    ty = top - y0 * scale

    body = "" if ground is None else f'<rect width="{size}" height="{size}" fill="{ground}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">{body}'
        f'<g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.6f})">'
        f'<path fill="{letter}" d="{d}"/></g>'
        f'<rect x="{cx - rule_w / 2:.3f}" y="{top + letter_h + gap:.3f}" '
        f'width="{rule_w:.3f}" height="{rule_t:.3f}" fill="{rule}"/></svg>'
    )


def lockup(wm: Wordmark, width: int, height: int, frac: float) -> str:
    """The full `aperto.wine` lockup for the splash, two-tone as on the masthead."""
    x0, y0, x1, y1 = wm.bounds("aperto.wine")
    w, h = x1 - x0, y1 - y0
    scale = (width * frac) / w
    word_h = h * scale
    rule_t = word_h * LOCKUP_RULE_T_F
    gap = word_h * LOCKUP_GAP_F

    top = (height - (word_h + gap + rule_t)) / 2
    tx = (width - w * scale) / 2 - x0 * scale
    ty = top - y0 * scale
    # `.wine` is placed by the advance of `aperto` plus one tracking step, so
    # the pair keeps the wordmark's own spacing rather than being two
    # independently centred words.
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">'
        f'<g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.6f})">'
        f'<path fill="{OX2}" d="{wm.path("aperto")}"/>'
        f'<g transform="translate({wm.advance("aperto") + wm.track:.1f} 0)">'
        f'<path fill="{OX3}" d="{wm.path(".wine")}"/></g></g>'
        f'<rect x="{tx + x0 * scale:.3f}" y="{top + word_h + gap:.3f}" '
        f'width="{w * scale:.3f}" height="{rule_t:.3f}" fill="{OX1}"/></svg>'
    )


def run(args: list[str], stdin: bytes | None = None) -> bytes:
    """subprocess.run that reports the tool's own complaint instead of a return code."""
    try:
        return subprocess.run(args, input=stdin, capture_output=True, check=True).stdout
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"{args[0]} failed: {e.stderr.decode(errors='replace').strip()}") from e


@dataclass(frozen=True)
class Job:
    path: Path
    svg: str
    width: int
    height: int
    opaque: bool
    # The mask circle this art has to survive, as a fraction of the width, or
    # None where nothing crops it. Kept on the job so there is one table to
    # keep in step rather than two.
    safe: float | None = None
    note: str = ""


def rasterize(job: Job) -> None:
    """SVG -> PNG. `opaque` strips the alpha channel entirely, which iOS requires
    of the app icon: an icon carrying alpha is rejected at submission."""
    png = run(["rsvg-convert", "-w", str(job.width), "-h", str(job.height)], job.svg.encode())
    tail = ["-background", PAPER, "-alpha", "remove", "-alpha", "off", f"PNG24:{job.path}"] if job.opaque \
        else ["-define", "png:color-type=6", f"PNG32:{job.path}"]
    run(["magick", "png:-", "-strip", *tail], png)


def verify(job: Job) -> str:
    w, h, alpha = run(["magick", "identify", "-format", "%w %h %A", str(job.path)]).decode().split()
    if (int(w), int(h)) != (job.width, job.height):
        raise SystemExit(f"{job.path.name}: expected {job.width}x{job.height}, got {w}x{h}")
    if (alpha not in ("Undefined", "False")) == job.opaque:
        raise SystemExit(
            f"{job.path.name}: alpha is {alpha!r}, wanted "
            f"{'no alpha channel' if job.opaque else 'an alpha channel'}"
        )
    return f"{job.path.name}  {w}x{h}  alpha={'no' if job.opaque else 'yes'}"


def check_safe_zone(job: Job) -> str:
    """Fail loudly if the art strays outside the mask circle it has to survive.

    Reads ImageMagick's trim box, which keys off the corner pixel — sound here
    because every artboard is either transparent or a flat full-bleed ground,
    so the trim finds the art and nothing else. Assumes a square canvas, which
    everything cropped by a mask is.
    """
    wh, x, y = run(["magick", str(job.path), "-format", "%@", "info:"]).decode().split("+")
    w, h = (int(v) for v in wh.split("x"))
    x, y, c = int(x), int(y), job.width / 2
    reach = max(math.hypot(px - c, py - c) for px in (x, x + w) for py in (y, y + h))
    safe = job.width * job.safe / 2
    if reach > safe:
        raise SystemExit(
            f"{job.path.name}: art reaches {reach:.0f}px from centre, {job.note} is {safe:.0f}px"
        )
    return f"{job.path.name}  art fits the {job.note} with {safe - reach:.0f}px to spare"


def main() -> None:
    missing = [f"{t} ({pkg})" for t, pkg in REQUIRED_TOOLS.items() if shutil.which(t) is None]
    if missing:
        raise SystemExit(f"not on PATH: {', '.join(missing)} — try `brew install imagemagick librsvg`")

    root = Path(__file__).resolve().parent.parent
    font = root / FONT_RELATIVE
    if not font.exists():
        raise SystemExit(f"{FONT_RELATIVE} is missing — run `npm install` in mobile/ first")

    images = root / "mobile" / "assets" / "images"
    public = root / "public"
    wm = Wordmark(font)

    # The web/app mark at its two grounds. Bound once so tuning the proportion
    # cannot change one output and not the other.
    web_mark = mark(wm, 512, 0.44, OX2, OX1, ground=PAPER)

    jobs = [
        # iOS/Expo app icon. Opaque paper ground — iOS rejects alpha here.
        Job(images / "icon.png", mark(wm, 1024, 0.44, OX2, OX1, ground=PAPER), 1024, 1024, True),
        # Android adaptive foreground, art held inside the mask circle. The
        # background layer is the flat `backgroundColor` token in app.config.js,
        # which beats shipping a PNG of one colour.
        Job(images / "android-icon-foreground.png", mark(wm, 1024, 0.32, OX2, OX1),
            1024, 1024, False, ADAPTIVE_SAFE, "adaptive mask circle"),
        # Android 13+ themed icon: one opaque colour on transparency, the system
        # discards the colour and re-tints from the wallpaper.
        Job(images / "android-icon-monochrome.png", mark(wm, 1024, 0.32, "#000000", "#000000"),
            1024, 1024, False, ADAPTIVE_SAFE, "adaptive mask circle"),
        # Android notification: 96x96 all-white on transparency, per the
        # expo-notifications plugin. Only the alpha channel is read.
        Job(images / "notification-icon.png", mark(wm, 96, 0.665, "#FFFFFF", "#FFFFFF"), 96, 96, False),
        # Expo web favicon.
        Job(images / "favicon.png", mark(wm, 196, 0.44, OX2, OX1, ground=PAPER), 196, 196, True),
        # Splash: the full lockup, transparent so the #F6F2E9 splash ground
        # shows through rather than being baked in at one tone.
        Job(images / "splash-icon.png", lockup(wm, 1600, 700, 0.78), 1600, 700, False),
        # The Rails app's own favicon and apple-touch-icon.
        Job(public / "icon.png", web_mark, 512, 512, True),
        # The PWA manifest's `purpose: "maskable"` entry, which is cropped to a
        # circle. It needs the tighter art the Android layers use; the icon
        # above would clear that circle by about three pixels.
        Job(public / "icon-maskable.png", mark(wm, 512, 0.32, OX2, OX1, ground=PAPER),
            512, 512, True, MASKABLE_SAFE, "maskable circle"),
    ]

    for job in jobs:
        rasterize(job)
        print(verify(job))
    (public / "icon.svg").write_text(web_mark + "\n")
    print("icon.svg  512x512 vector")

    for job in jobs:
        if job.safe is not None:
            print(check_safe_zone(job))


if __name__ == "__main__":
    sys.exit(main())
