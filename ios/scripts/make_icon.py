#!/usr/bin/env python3
#
# Graph89 Remastered - TI graphing calculator emulator for iPhone
# Copyright (C) 2026 JH
# Based on Graph89, Copyright (C) 2012-2013 Dritan Hashorva (modified and rewritten in Swift, 2026).
#
# This program is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version. This program is distributed in the hope that it
# will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.
#
"""Makes the iOS app icon from the Android launcher icon, as the same artwork.

The Android adaptive icon is two 108x108 vector drawables (ic_launcher_background.xml and
ic_launcher_foreground.xml) of which launchers show the middle 72x72; the Play Store icon
(app/src/main/ic_launcher-playstore.png) frames the same region. This draws both layers into one
full-bleed, opaque square: iOS masks the corners itself, and the App Store icon may not have alpha.

Only Pillow is needed. The paths are flattened into polygons here and filled by a scanline
rasteriser at 4x the size, then downsampled.

    python ios/scripts/make_icon.py              # writes the AppIcon set of the asset catalog
    python ios/scripts/make_icon.py --out x.png  # writes only the image, e.g. for a preview
"""

import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops

REPO = Path(__file__).resolve().parents[2]
DRAWABLES = REPO / 'app' / 'src' / 'main' / 'res' / 'drawable'
LAYERS = [DRAWABLES / 'ic_launcher_background.xml', DRAWABLES / 'ic_launcher_foreground.xml']
CATALOG = REPO / 'ios' / 'Graph89' / 'Resources' / 'Assets.xcassets'
ICON_SET = CATALOG / 'AppIcon.appiconset'

A = '{http://schemas.android.com/apk/res/android}'
AAPT = '{http://schemas.android.com/aapt}'

# Launchers show the middle 72dp of the 108dp layers, so 18dp is cut off at each side.
INSET = 18 / 108
# How far the flattened outlines may stray from the true curves, in supersampled pixels.
TOLERANCE = 0.1


# ---------------------------------------------------------------------------------------------
# Affine matrices (a, b, c, d, e, f): x' = a*x + c*y + e, y' = b*x + d*y + f

def concat(m, n):
    """The matrix that applies n, then m."""
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2,
            a * c2 + c * d2, b * c2 + d * d2,
            a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def scale_of(m):
    """The mean scale of m, for stroke widths and flattening tolerances."""
    return math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))


def translate(x, y):
    return (1.0, 0.0, 0.0, 1.0, x, y)


def group_matrix(el):
    """A <group>'s transform, composed as VectorDrawable does: pivot, scale, rotate, translate."""
    px = float(el.get(A + 'pivotX', '0'))
    py = float(el.get(A + 'pivotY', '0'))
    sx = float(el.get(A + 'scaleX', '1'))
    sy = float(el.get(A + 'scaleY', '1'))
    r = math.radians(float(el.get(A + 'rotation', '0')))
    tx = float(el.get(A + 'translateX', '0'))
    ty = float(el.get(A + 'translateY', '0'))
    m = translate(-px, -py)
    m = concat((sx, 0.0, 0.0, sy, 0.0, 0.0), m)
    m = concat((math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0.0, 0.0), m)
    return concat(translate(tx + px, ty + py), m)


# ---------------------------------------------------------------------------------------------
# Colours and gradients

def parse_color(text):
    """#RGB, #ARGB, #RRGGBB or #AARRGGBB as (r, g, b, a). Colour resources are not resolved."""
    s = text.strip()
    if not s.startswith('#'):
        raise ValueError(f'unsupported colour {text!r}: only #-literals are understood')
    h = s[1:]
    if len(h) in (3, 4):
        h = ''.join(ch * 2 for ch in h)
    if len(h) == 6:
        h = 'ff' + h
    if len(h) != 8:
        raise ValueError(f'bad colour {text!r}')
    v = int(h, 16)
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255, (v >> 24) & 255)


class Gradient:
    """A linear <gradient>, from its <item> stops or its start/center/end colours."""

    def __init__(self, el):
        kind = el.get(A + 'type', 'linear')
        if kind != 'linear':
            raise ValueError(f'{kind} gradients are not supported')
        self.start = (float(el.get(A + 'startX', '0')), float(el.get(A + 'startY', '0')))
        self.end = (float(el.get(A + 'endX', '0')), float(el.get(A + 'endY', '0')))
        self.tile = el.get(A + 'tileMode', 'clamp')
        items = el.findall('item')
        if items:
            stops = [(float(i.get(A + 'offset')), parse_color(i.get(A + 'color'))) for i in items]
        else:
            stops = [(0.0, parse_color(el.get(A + 'startColor')))]
            if el.get(A + 'centerColor') is not None:
                stops.append((0.5, parse_color(el.get(A + 'centerColor'))))
            stops.append((1.0, parse_color(el.get(A + 'endColor'))))
        self.stops = sorted(stops, key=lambda stop: stop[0])

    def color_at(self, t):
        if self.tile == 'repeat':
            t -= math.floor(t)
        elif self.tile == 'mirror':
            t = abs(t) % 2.0
            if t > 1.0:
                t = 2.0 - t
        t = min(max(t, 0.0), 1.0)
        stops = self.stops
        if t <= stops[0][0]:
            return stops[0][1]
        for (o0, c0), (o1, c1) in zip(stops, stops[1:]):
            if t <= o1:
                u = 0.0 if o1 == o0 else (t - o0) / (o1 - o0)
                return tuple(round(a + (b - a) * u) for a, b in zip(c0, c1))
        return stops[-1][1]


def gradient_image(grad, s, e, box):
    """The gradient (from pixel s to pixel e) over box, as RGBA: a strip along it, stretched across."""
    x0, y0, x1, y1 = box
    size = (x1 - x0, y1 - y0)
    dx, dy = e[0] - s[0], e[1] - s[1]
    length2 = dx * dx + dy * dy
    if length2 == 0:
        return Image.new('RGBA', size, grad.stops[-1][1])
    ts = [((x - s[0]) * dx + (y - s[1]) * dy) / length2 for x in (x0, x1) for y in (y0, y1)]
    t0, t1 = min(ts), max(ts)
    if t1 - t0 < 1e-9:
        return Image.new('RGBA', size, grad.color_at(t0))
    n = 4096
    strip = Image.new('RGBA', (n, 1))
    strip.putdata([grad.color_at(t0 + (t1 - t0) * (i + 0.5) / n) for i in range(n)])
    # Strip x = (t - t0) * n / (t1 - t0), with t taken at each output pixel's centre.
    k = n / (t1 - t0) / length2
    c = k * ((x0 - s[0]) * dx + (y0 - s[1]) * dy) - t0 * n / (t1 - t0)
    return strip.transform(size, Image.Transform.AFFINE, (k * dx, k * dy, c, 0.0, 0.0, 0.5),
                           resample=Image.Resampling.BILINEAR)


# ---------------------------------------------------------------------------------------------
# Path data, flattened into polylines

_NUMBER = re.compile(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


class _Scanner:
    def __init__(self, text):
        self.text = text
        self.pos = 0

    def _skip(self):
        while self.pos < len(self.text) and self.text[self.pos] in ' \t\r\n,':
            self.pos += 1

    def done(self):
        self._skip()
        return self.pos >= len(self.text)

    def has_number(self):
        self._skip()
        return self.pos < len(self.text) and self.text[self.pos] in '0123456789+-.'

    def command(self):
        self._skip()
        c = self.text[self.pos]
        if c not in 'MmLlHhVvCcSsQqTtAaZz':
            raise ValueError(f'bad path command {c!r} at {self.pos} in {self.text!r}')
        self.pos += 1
        return c

    def number(self):
        self._skip()
        m = _NUMBER.match(self.text, self.pos)
        if m is None:
            raise ValueError(f'number expected at {self.pos} in {self.text!r}')
        self.pos = m.end()
        return float(m.group())

    def flag(self):
        """An arc flag: a single 0 or 1, which may run straight into the next number."""
        self._skip()
        c = self.text[self.pos:self.pos + 1]
        if c not in ('0', '1'):
            raise ValueError(f'arc flag expected at {self.pos} in {self.text!r}')
        self.pos += 1
        return c == '1'


def _cubic(p0, p1, p2, p3, tol):
    # Uniform steps stray at most max|B''| / (8 n^2), and |B''| <= 6 max|P(i) - 2P(i+1) + P(i+2)|.
    ddx = max(abs(p0[0] - 2 * p1[0] + p2[0]), abs(p1[0] - 2 * p2[0] + p3[0]))
    ddy = max(abs(p0[1] - 2 * p1[1] + p2[1]), abs(p1[1] - 2 * p2[1] + p3[1]))
    n = max(1, math.ceil(math.sqrt(0.75 * math.hypot(ddx, ddy) / tol)))
    pts = []
    for i in range(1, n + 1):
        t = i / n
        u = 1.0 - t
        a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def _quad(p0, p1, p2, tol):
    ddx = abs(p0[0] - 2 * p1[0] + p2[0])
    ddy = abs(p0[1] - 2 * p1[1] + p2[1])
    n = max(1, math.ceil(math.sqrt(math.hypot(ddx, ddy) / (4 * tol))))
    pts = []
    for i in range(1, n + 1):
        t = i / n
        u = 1.0 - t
        a, b, c = u * u, 2 * u * t, t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return pts


def _arc(p0, rx, ry, angle, large, sweep, p1, tol):
    """An elliptical arc, by the endpoint-to-centre conversion of SVG 1.1 appendix F.6.5."""
    (x1, y1), (x2, y2) = p0, p1
    if (x1, y1) == (x2, y2):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [p1]
    phi = math.radians(angle)
    cp, sp = math.cos(phi), math.sin(phi)
    hx, hy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cp * hx + sp * hy
    y1p = -sp * hx + cp * hy
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:  # radii too small for the chord: scale them up just enough
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0.0, num / den))
    if large == sweep:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def angle_between(ux, uy, vx, vy):
        return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta = angle_between(1.0, 0.0, ux, uy)
    delta = angle_between(ux, uy, vx, vy)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi
    r = max(rx, ry)
    step = 2 * math.acos(1 - tol / r) if tol < r else math.pi / 2
    n = max(1, math.ceil(abs(delta) / step))
    pts = []
    for i in range(1, n):
        t = theta + delta * i / n
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        pts.append((cp * ex - sp * ey + cx, sp * ex + cp * ey + cy))
    pts.append(p1)
    return pts


def flatten_path(data, tol):
    """pathData as subpaths [(points, closed)], each point within tol of the true outline."""
    sc = _Scanner(data)
    subpaths = []
    current = None              # the open subpath's points; None before M or after Z
    x = y = 0.0                 # current point
    start = (0.0, 0.0)          # where the current subpath began
    ctrl = None                 # the last control point, which S and T reflect
    prev = ''                   # the last command, upper case

    def flush(closed):
        # A lone moveTo draws nothing; a zero-length segment still draws its caps.
        if current is not None and (closed or len(current) > 1):
            subpaths.append((current, closed))

    while not sc.done():
        cmd = sc.command()
        op = cmd.upper()
        rel = cmd != op
        if op == 'Z':
            flush(True)
            current = None
            x, y = start
            ctrl, prev = None, 'Z'
            continue
        while True:
            ox, oy = (x, y) if rel else (0.0, 0.0)
            p0 = (x, y)
            if op == 'M':
                flush(False)
                x, y = ox + sc.number(), oy + sc.number()
                start = (x, y)
                current = [start]
                ctrl, prev = None, 'M'
                op = 'L'  # further pairs are lineTos
                if not sc.has_number():
                    break
                continue
            if current is None:
                current = [start]
            if op == 'L':
                x, y = ox + sc.number(), oy + sc.number()
                current.append((x, y))
                ctrl = None
            elif op == 'H':
                x = ox + sc.number()
                current.append((x, y))
                ctrl = None
            elif op == 'V':
                y = oy + sc.number()
                current.append((x, y))
                ctrl = None
            elif op in 'CS':
                if op == 'C':
                    c1 = (ox + sc.number(), oy + sc.number())
                else:
                    c1 = (2 * x - ctrl[0], 2 * y - ctrl[1]) if prev in ('C', 'S') and ctrl else p0
                c2 = (ox + sc.number(), oy + sc.number())
                x, y = ox + sc.number(), oy + sc.number()
                current.extend(_cubic(p0, c1, c2, (x, y), tol))
                ctrl = c2
            elif op in 'QT':
                if op == 'Q':
                    c1 = (ox + sc.number(), oy + sc.number())
                else:
                    c1 = (2 * x - ctrl[0], 2 * y - ctrl[1]) if prev in ('Q', 'T') and ctrl else p0
                x, y = ox + sc.number(), oy + sc.number()
                current.extend(_quad(p0, c1, (x, y), tol))
                ctrl = c1
            elif op == 'A':
                rx, ry, angle = sc.number(), sc.number(), sc.number()
                large, sweep = sc.flag(), sc.flag()
                x, y = ox + sc.number(), oy + sc.number()
                current.extend(_arc(p0, rx, ry, angle, large, sweep, (x, y), tol))
                ctrl = None
            prev = op
            if not sc.has_number():
                break
    flush(False)
    return subpaths


# ---------------------------------------------------------------------------------------------
# Strokes, as polygons whose union is the stroke

def _area2(poly):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]))


def _oriented(poly):
    """poly wound one way round, so that overlapping pieces add up under the non-zero rule."""
    return poly if _area2(poly) >= 0 else poly[::-1]


def _circle(cx, cy, r):
    n = 8
    if r > TOLERANCE:
        n = max(8, math.ceil(math.pi / math.acos(1 - TOLERANCE / r)))
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def _dedupe(pts):
    out = [pts[0]]
    for p in pts[1:]:
        if math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 1e-9:
            out.append(p)
    return out


def stroke_polygons(subpaths, width, cap, join, miter_limit):
    hw = width / 2
    out = []
    for pts, closed in subpaths:
        pts = _dedupe(pts)
        if closed and len(pts) > 2 and math.hypot(pts[0][0] - pts[-1][0], pts[0][1] - pts[-1][1]) <= 1e-9:
            pts = pts[:-1]
        if len(pts) == 1:
            # A zero-length segment shows only its caps.
            px, py = pts[0]
            if cap == 'round':
                out.append(_circle(px, py, hw))
            elif cap == 'square':
                out.append([(px - hw, py - hw), (px + hw, py - hw), (px + hw, py + hw), (px - hw, py + hw)])
            continue
        if not closed and cap == 'square':
            # Square caps lengthen the ends by half the width.
            (ax, ay), (bx, by) = pts[0], pts[1]
            d = math.hypot(bx - ax, by - ay)
            pts[0] = (ax - (bx - ax) / d * hw, ay - (by - ay) / d * hw)
            (ax, ay), (bx, by) = pts[-1], pts[-2]
            d = math.hypot(bx - ax, by - ay)
            pts[-1] = (ax - (bx - ax) / d * hw, ay - (by - ay) / d * hw)
        segs = list(zip(pts, pts[1:] + (pts[:1] if closed else [])))
        dirs = []
        for (x0, y0), (x1, y1) in segs:
            d = math.hypot(x1 - x0, y1 - y0)
            ux, uy = (x1 - x0) / d, (y1 - y0) / d
            dirs.append((ux, uy))
            nx, ny = -uy * hw, ux * hw
            out.append(_oriented([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]))
        # Joins, between each segment and the next.
        pairs = range(len(segs)) if closed else range(len(segs) - 1)
        for i in pairs:
            vx, vy = segs[i][1]
            (ux0, uy0), (ux1, uy1) = dirs[i], dirs[(i + 1) % len(dirs)]
            if join == 'round':
                out.append(_circle(vx, vy, hw))
                continue
            cross = ux0 * uy1 - uy0 * ux1
            if abs(cross) < 1e-12 and ux0 * ux1 + uy0 * uy1 > 0:
                continue  # straight on
            side = -1.0 if cross > 0 else 1.0  # the outer side of the turn
            n0 = (-uy0 * hw * side, ux0 * hw * side)
            n1 = (-uy1 * hw * side, ux1 * hw * side)
            piece = [(vx, vy), (vx + n0[0], vy + n0[1])]
            sx, sy = n0[0] + n1[0], n0[1] + n1[1]
            s2 = sx * sx + sy * sy
            if join == 'miter' and s2 > 1e-12 and 2 * hw / math.sqrt(s2) <= miter_limit:
                k = 2 * hw * hw / s2
                piece.append((vx + sx * k, vy + sy * k))
            piece.append((vx + n1[0], vy + n1[1]))
            out.append(_oriented(piece))
        if not closed and cap == 'round':
            out.append(_circle(pts[0][0], pts[0][1], hw))
            out.append(_circle(pts[-1][0], pts[-1][1], hw))
    return out


# ---------------------------------------------------------------------------------------------
# Rasterising

def rasterise(size, polygons, even_odd=False):
    """A mask of the pixels whose centres lie inside the polygons (non-zero or even-odd rule)."""
    w, h = size
    edges = []
    for poly in polygons:
        for i in range(len(poly)):
            x0, y0 = poly[i - 1]
            x1, y1 = poly[i]
            if y0 == y1:
                continue
            winding = 1
            if y0 > y1:
                x0, y0, x1, y1 = x1, y1, x0, y0
                winding = -1
            first = max(0, math.ceil(y0 - 0.5))  # rows whose centre is in [y0, y1)
            last = min(h, math.ceil(y1 - 0.5))
            if first >= last:
                continue
            slope = (x1 - x0) / (y1 - y0)
            edges.append((first, last, x0 + (first + 0.5 - y0) * slope, slope, winding))
    mask = Image.new('L', size, 0)
    if not edges:
        return mask
    edges.sort(key=lambda edge: edge[0])
    active = []
    k = 0
    row = edges[0][0]
    end = max(edge[1] for edge in edges)
    while row < end:
        while k < len(edges) and edges[k][0] <= row:
            _, last, x, slope, winding = edges[k]
            active.append([last, x, slope, winding])
            k += 1
        active = [edge for edge in active if edge[0] > row]
        wind = 0
        left = 0.0
        for x, winding in sorted((edge[1], edge[3]) for edge in active):
            was = (wind & 1) if even_odd else wind != 0
            wind += winding
            now = (wind & 1) if even_odd else wind != 0
            if now and not was:
                left = x
            elif was and not now:
                a = max(0, math.ceil(left - 0.5))
                b = min(w, math.ceil(x - 0.5))
                if a < b:
                    mask.paste(255, (a, row, b, row + 1))
        for edge in active:
            edge[1] += edge[2]
        row += 1
    return mask


def draw(canvas, polygons, even_odd, paint, alpha):
    mask = rasterise(canvas.size, polygons, even_odd)
    box = mask.getbbox()
    if box is None:
        return
    mask = mask.crop(box)
    if paint[0] == 'solid':
        layer = Image.new('RGBA', mask.size, paint[1])
    else:
        layer = gradient_image(paint[1], paint[2], paint[3], box)
    coverage = ImageChops.multiply(layer.getchannel('A'), mask)
    if alpha < 1:
        coverage = coverage.point(lambda v: round(v * alpha))
    layer.putalpha(coverage)
    canvas.alpha_composite(layer, dest=box[:2])


# ---------------------------------------------------------------------------------------------
# Vector drawables

def _gradient_attr(el, name):
    """A gradient given inline as <aapt:attr name="android:name">, or None."""
    for attr in el.findall(AAPT + 'attr'):
        if attr.get('name') == 'android:' + name:
            g = attr.find('gradient')
            if g is None:
                raise ValueError(f'android:{name} must hold a <gradient>')
            return g
    return None


def _paint(el, name, matrix):
    g = _gradient_attr(el, name)
    if g is not None:
        grad = Gradient(g)
        return ('gradient', grad, apply(matrix, *grad.start), apply(matrix, *grad.end))
    value = el.get(A + name)
    if value is None:
        return None
    rgba = parse_color(value)
    return None if rgba[3] == 0 else ('solid', rgba)


def _path_shapes(el, matrix, alpha):
    """A <path> as (polygons, even_odd, paint, alpha): its fill, then its stroke, as Android draws them."""
    for name, default in (('trimPathStart', 0.0), ('trimPathEnd', 1.0), ('trimPathOffset', 0.0)):
        if float(el.get(A + name, default)) != default:
            raise ValueError(f'android:{name} is not supported')
    scale = scale_of(matrix)
    subpaths = flatten_path(el.get(A + 'pathData', ''), TOLERANCE / scale)
    pixels = [([apply(matrix, px, py) for px, py in pts], closed) for pts, closed in subpaths]
    shapes = []
    fill = _paint(el, 'fillColor', matrix)
    if fill is not None:
        even_odd = el.get(A + 'fillType', 'nonZero') == 'evenOdd'
        polygons = [pts for pts, _ in pixels if len(pts) >= 3]
        shapes.append((polygons, even_odd, fill, alpha * float(el.get(A + 'fillAlpha', '1'))))
    stroke = _paint(el, 'strokeColor', matrix)
    width = float(el.get(A + 'strokeWidth', '0')) * scale
    if stroke is not None and width > 0:
        polygons = stroke_polygons(pixels, width, el.get(A + 'strokeLineCap', 'butt'),
                                   el.get(A + 'strokeLineJoin', 'miter'),
                                   float(el.get(A + 'strokeMiterLimit', '4')))
        shapes.append((polygons, False, stroke, alpha * float(el.get(A + 'strokeAlpha', '1'))))
    return shapes


def _walk(el, matrix, alpha, shapes):
    for child in el:
        if child.tag == 'group':
            _walk(child, concat(matrix, group_matrix(child)), alpha, shapes)
        elif child.tag == 'path':
            shapes.extend(_path_shapes(child, matrix, alpha))
        elif child.tag == 'clip-path':
            raise ValueError('<clip-path> is not supported')


def load_layer(path, size):
    """An adaptive icon layer's shapes, in pixels of a size x size icon showing the layer's middle."""
    root = ET.parse(path).getroot()
    vw = float(root.get(A + 'viewportWidth'))
    vh = float(root.get(A + 'viewportHeight'))
    k = size / (1 - 2 * INSET)  # the whole layer, in pixels
    to_pixels = (k / vw, 0.0, 0.0, k / vh, -INSET * k, -INSET * k)
    shapes = []
    _walk(root, to_pixels, float(root.get(A + 'alpha', '1')), shapes)
    return shapes


def render(size):
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    for layer in LAYERS:
        for polygons, even_odd, paint, alpha in load_layer(layer, size):
            draw(canvas, polygons, even_odd, paint, alpha)
    return canvas


# ---------------------------------------------------------------------------------------------

def write_json(path, obj):
    """JSON as Xcode writes it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(obj, indent=2, separators=(',', ' : ')) + '\n'
    path.write_text(text, encoding='utf-8', newline='\n')


def main():
    parser = argparse.ArgumentParser(description='Makes the iOS app icon from the Android launcher icon.')
    parser.add_argument('--size', type=int, default=1024, help='icon size in pixels (default 1024)')
    parser.add_argument('--supersample', type=int, default=4, help='render this many times larger, then downsample (default 4)')
    parser.add_argument('--out', type=Path, help='write only the image, here, instead of the asset catalog')
    args = parser.parse_args()

    big = render(args.size * args.supersample)
    if big.getchannel('A').getextrema() != (255, 255):
        sys.exit('the layers leave part of the icon transparent, but iOS app icons must be opaque')
    icon = big.convert('RGB').resize((args.size, args.size), Image.Resampling.LANCZOS)

    out = args.out if args.out is not None else ICON_SET / 'AppIcon.png'
    out.parent.mkdir(parents=True, exist_ok=True)
    icon.save(out, optimize=True)
    if args.out is None:
        # One 1024x1024 image for every size (Xcode 14 and later).
        write_json(ICON_SET / 'Contents.json', {
            'images': [{'filename': out.name, 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
            'info': {'author': 'xcode', 'version': 1},
        })
        if not (CATALOG / 'Contents.json').exists():
            write_json(CATALOG / 'Contents.json', {'info': {'author': 'xcode', 'version': 1}})
    print(f'{out} ({args.size}x{args.size})')


if __name__ == '__main__':
    main()
