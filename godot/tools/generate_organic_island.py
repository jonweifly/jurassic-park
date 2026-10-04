"""Bake the approved natural-island prototype into the existing Godot map format.

Only this map's data/design files are written. No scene, original terrain, saves
or prototype is replaced. Run with Python 3; no third-party modules are needed.
"""
import argparse
import json
import math
import heapq
import random
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/map_candidates/organic_island_prototype_v1.json"
SIDE = 128
SEA = 0.55
SEED = 20261004


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def curve(points, closed=False, steps=4):
    """Catmull-Rom interpolation keeps bays, ridges and paths organic."""
    result = []
    for i in range(len(points) if closed else len(points) - 1):
        a, b = points[(i - 1) % len(points)] if closed or i else points[0], points[i]
        c = points[(i + 1) % len(points)]
        d = points[(i + 2) % len(points)] if closed else points[min(i + 2, len(points) - 1)]
        for step in range(steps):
            t = step / steps
            result.append(tuple(.5 * (2 * b[k] + (-a[k] + c[k]) * t
                + (2 * a[k] - 5 * b[k] + 4 * c[k] - d[k]) * t * t
                + (-a[k] + 3 * b[k] - 3 * c[k] + d[k]) * t ** 3) for k in (0, 1)))
    if not closed: result.append(tuple(points[-1]))
    return result


def segments(points, closed=False):
    return list(zip(points, points[1:] + points[:1] if closed else points[1:]))


def distance_segment(x, z, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dz * dz
    t = max(0, min(1, ((x - a[0]) * dx + (z - a[1]) * dz) / length)) if length else 0
    return math.hypot(x - a[0] - t * dx, z - a[1] - t * dz)


def inside(x, z, polygon):
    hit = False
    for a, b in segments(polygon, True):
        if (a[1] > z) != (b[1] > z) and x < a[0] + (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]):
            hit = not hit
    return hit


def polygon_distance(x, z, polygon):
    distance = min(distance_segment(x, z, a, b) for a, b in segments(polygon, True))
    return distance if inside(x, z, polygon) else -distance


def line_distance(x, z, line):
    return min(distance_segment(x, z, a, b) for a, b in segments(line))


def cell_at(world):
    return int((world[0] + 128) // 2), int((world[1] + 128) // 2)


def world_at(cell):
    return cell[0] * 2 - 127, cell[1] * 2 - 127


def flood(cells, origin):
    if origin not in cells: return set()
    seen, pending = {origin}, deque([origin])
    while pending:
        x, y = pending.popleft()
        for c in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if c in cells and c not in seen:
                seen.add(c)
                pending.append(c)
    return seen


def build_map(revision=3):
    map_id = f"organic-island-v{revision}"
    prototype = json.loads(SOURCE.read_text(encoding="utf-8"))
    rng = random.Random(SEED)
    coast = curve(prototype["island_outline"]["points"], True)
    forests = [{**p, "polygon": curve(p["polygon"], True)} for p in prototype["forests"]]
    if revision >= 2:
        # The ridge leaves too little dry forest on the east coast. Let its
        # woodland wrap around the northern shoulder instead of crowding camps.
        forests[2]["polygon"] = curve([[13, -88], [37, -80], [59, -73], [77, -59], [90, -42],
                                       [85, -19], [68, -20], [46, -30], [30, -49], [31, -64], [17, -66]], True)
    ridges = [{**p, "polygon": curve(p["polygon"], True)} for p in prototype["mountain_barriers"]]
    if revision >= 3:
        outlines = [
            [[-29, -85], [-18, -70], [-12, -57], [6, -49], [20, -33], [13, -29], [1, -43], [-21, -55], [-28, -70], [-34, -82]],
            [[36, -65], [48, -55], [58, -43], [56, -30], [46, -21], [39, -25], [47, -39], [43, -50], [31, -57]],
            [[-104, -4], [-93, -3], [-100, 9], [-96, 22], [-83, 31], [-76, 33], [-84, 39], [-103, 28], [-111, 15]],
        ]
        for ridge, outline in zip(ridges, outlines):
            ridge["polygon"] = curve(outline, True)
    marsh = curve(prototype["wetland"]["polygon"], True)
    camps = [
        {"id": "landing_grove", "label": "西岸背风林地", "world": [-85, -39], "extent": [13, 10], "protection": "西北岸岩棚与北侧厚林", "phase": "early"},
        {"id": "north_grove", "label": "北部林间凹地", "world": [-57, -53], "extent": [10, 9], "protection": "原始森林三侧环抱", "phase": "mid"},
        {"id": "south_terrace", "label": "南部溪旁台地", "world": [-39, 47], "extent": [12, 9], "protection": "西侧断崖与南部密林", "phase": "mid"},
        {"id": "east_shelf", "label": "东部岩脊林缘", "world": [75, -37], "extent": [10, 9], "protection": "西侧岩脊与东部雨林", "phase": "late"},
    ]
    forest_sites, rock_refuges = [], []
    if revision >= 2:
        forest_sites = [
            {"id": "west_inner_grove", "label": "西林深处空地", "world": [-91, -24], "extent": [8, 6], "protection": "背岸厚林与弯曲林隙", "phase": "early", "kind": "forest_interior"},
            {"id": "north_inner_grove", "label": "北林老树凹地", "world": [-48, -77], "extent": [9, 7], "protection": "两片厚林夹出的林下空间", "phase": "mid", "kind": "forest_interior"},
            {"id": "south_inner_grove", "label": "南林隐蔽台地", "world": [-56, 29], "extent": [9, 7], "protection": "溪岸与多层树丛护住侧翼", "phase": "mid", "kind": "forest_interior"},
            {"id": "east_inner_grove", "label": "东北老林空隙", "world": [22, -75], "extent": [9, 7], "protection": "山脊北肩与东北厚林", "phase": "late", "kind": "forest_interior"},
            {"id": "west_canopy_hollow", "label": "西林岩肩内凹地", "world": [-39, -45], "extent": [8, 6], "protection": "老树群与东侧岩肩围合", "phase": "mid", "kind": "forest_interior"},
            {"id": "south_canopy_hollow", "label": "南林深处天窗", "world": [-7, 47], "extent": [8, 6], "protection": "厚林围出的小片林下空间", "phase": "mid", "kind": "forest_interior"},
        ]
        rock_refuges = [
            {"id": "west_rock_hollow", "label": "西侧岩抱谷", "world": [-88, 12], "extent": [10, 9], "protection": "断崖岩壁三面围合，东侧谷口可进", "phase": "mid", "kind": "rock_hollow"},
            {"id": "east_rock_hollow", "label": "东侧岩脊凹谷", "world": [46, -40], "extent": [9, 8], "protection": "岩肩围住平坦谷底，东南裂隙可进", "phase": "late", "kind": "rock_hollow"},
        ]
        for c in camps:
            c["kind"] = "forest_edge"
        camps += forest_sites + rock_refuges
    stepping_sites = []
    if revision >= 3:
        stepping_sites = [
            {"id": "north_coast_stop", "label": "北岸老林落脚点", "world": [-79, -72], "extent": [4.5, 4], "kind": "forest_stop"},
            {"id": "north_ridge_stop", "label": "北岩肩林隙", "world": [-13, -72], "extent": [4.5, 4], "kind": "forest_stop"},
            {"id": "east_coast_stop", "label": "东岸林间落脚点", "world": [85, 9], "extent": [5, 4], "kind": "forest_stop"},
            {"id": "south_coast_stop", "label": "南岸老树洼地", "world": [-53, 79], "extent": [5, 4], "kind": "forest_stop"},
            {"id": "wetland_bank_stop", "label": "湿地林岸中转地", "world": [57, 21], "extent": [5, 4], "kind": "forest_stop"},
            {"id": "west_hollow_wood", "label": "西岩谷补给林隙", "world": [-76, 17], "extent": [5, 4], "kind": "forest_stop"},
            {"id": "east_hollow_wood", "label": "东岩谷补给林隙", "world": [35, -35], "extent": [5, 4], "kind": "forest_stop"},
        ]
    spawns = [{"id": "west_landing", "label": "西岸登陆点", "world": camps[0]["world"]}]
    extraction = [{"id": "valley_landing", "label": "河谷救援空地", "world": [-19, 1], "extent": [9, 9]}]
    gold = [
        {"id": "west_exposure", "label": "断崖露头", "world": [-53, -1], "radius": 6, "fields": 2, "reserve_gold": 400, "phase": "mid"},
        {"id": "south_sediment", "label": "溪旁沉积矿层", "world": [-25, 59], "radius": 5, "fields": 2, "reserve_gold": 700, "phase": "mid"},
        {"id": "east_canyon", "label": "东峡谷矿层", "world": [69, -11], "radius": 6, "fields": 3, "reserve_gold": 1100, "phase": "late"},
        {"id": "north_outcrop", "label": "山口深层矿脉", "world": [23, -49], "radius": 5, "fields": 3, "reserve_gold": 1400, "phase": "late"},
    ]
    route_defs = [dict(p) for p in prototype["routes"]]
    route_defs += [
        {"id": "valley_south", "label": "西支流林缘", "kind": "secondary", "tier": "mid", "path": [[4, -2], [-17, 9], [-34, 27], [-45, 39], [-39, 47], [-59, 55], [-69, 57]]},
        {"id": "north_grove_spur", "label": "北林凹地通道", "kind": "secondary", "tier": "mid", "path": [[-63, -31], [-62, -39], [-57, -53], [-68, -70], [-72, -79]]},
        {"id": "east_grove_spur", "label": "东林岩缘", "kind": "secondary", "tier": "late", "path": [[70, -14], [74, -26], [75, -37], [70, -49]]},
        {"id": "west_outcrop_spur", "label": "西侧岩脚", "kind": "secondary", "tier": "mid", "path": [[-40, -20], [-51, -13], [-53, -1]]},
        {"id": "north_outcrop_spur", "label": "山口岩棚", "kind": "secondary", "tier": "late", "path": [[19, -39], [23, -49]]},
        {"id": "south_outcrop_spur", "label": "南溪沉积岸", "kind": "secondary", "tier": "mid", "path": [[-28, 70], [-25, 59]]},
        {"id": "wetland_coast", "label": "湿地高岸", "kind": "secondary", "tier": "mid", "path": [[60, 54], [51, 65], [35, 71]]},
        {"id": "rescue_approach", "label": "河谷林缘空地", "kind": "secondary", "tier": "mid", "path": [[-18, -9], [-19, 1]]},
    ]
    if revision >= 2:
        # These narrow meanders join interior clearings to existing valleys.
        # Dense thickets between them remain intact; there is no paved road grid.
        route_defs += [
            {"id": "west_understory", "label": "西林弯曲林隙", "kind": "forest_gap", "tier": "early", "width": 2.6,
             "path": [[-85, -39], [-92, -35], [-95, -29], [-91, -24], [-85, -18], [-77, -23], [-69, -27], [-63, -31]]},
            {"id": "north_understory", "label": "北林老树间隙", "kind": "forest_gap", "tier": "mid", "width": 2.8,
             "path": [[-57, -53], [-50, -59], [-55, -65], [-48, -77], [-39, -79], [-33, -70], [-36, -58], [-32, -45], [-25, -25]]},
            {"id": "south_understory", "label": "南林溪岸林隙", "kind": "forest_gap", "tier": "mid", "width": 2.8,
             "path": [[-34, 27], [-43, 22], [-51, 24], [-56, 29], [-60, 38], [-51, 42], [-39, 47]]},
            {"id": "east_understory", "label": "东林岩肩林隙", "kind": "forest_gap", "tier": "late", "width": 2.6,
             "path": [[23, -49], [31, -57], [29, -67], [22, -75], [32, -74], [45, -71], [58, -65], [68, -57], [70, -49]]},
            {"id": "west_canopy_gaps", "label": "西林树群夹隙", "kind": "forest_gap", "tier": "mid", "width": 2.8,
             "path": [[-57, -53], [-47, -52], [-44, -47], [-39, -45], [-34, -39], [-36, -32], [-40, -20]]},
            {"id": "south_canopy_gaps", "label": "南林深处枝隙", "kind": "forest_gap", "tier": "mid", "width": 3.6,
             "path": [[-39, 47], [-28, 43], [-20, 48], [-14, 54], [-7, 47], [1, 44], [11, 37], [20, 30], [28, 27]]},
            {"id": "south_canopy_loop", "label": "南林潮湿洼地缝隙", "kind": "forest_gap", "tier": "mid", "width": 3.6,
             "path": [[-7, 47], [-8, 59], [1, 64], [12, 58], [18, 49], [25, 42], [28, 27]]},
            {"id": "west_hollow_entry", "label": "西侧岩谷裂口", "kind": "rock_pass", "tier": "mid", "width": 5.6,
             "path": [[-53, -1], [-61, 4], [-70, 7], [-78, 13], [-88, 12]]},
            {"id": "east_hollow_entry", "label": "东侧岩谷裂隙", "kind": "rock_pass", "tier": "late", "width": 5.6,
             "path": [[69, -11], [65, -23], [58, -30], [49, -34], [46, -40]]},
        ]
    if revision >= 3:
        route_defs += [
            {"id": "north_coast_link", "label": "北岸森林内缘", "kind": "forest_gap", "tier": "mid", "width": 3.4,
             "path": [[-85, -39], [-87, -58], [-79, -72], [-68, -79], [-48, -77], [-33, -83], [-13, -72], [4, -76], [22, -75]]},
            {"id": "north_ridge_link", "label": "北岩肩绕行林隙", "kind": "forest_gap", "tier": "mid", "width": 3.4,
             "path": [[-13, -72], [-2, -63], [13, -59], [23, -49]]},
            {"id": "west_hollow_link", "label": "西岩谷与溪林相连", "kind": "rock_pass", "tier": "mid", "width": 4.8,
             "path": [[-88, 12], [-76, 17], [-66, 22], [-56, 29]]},
            {"id": "east_hollow_link", "label": "东岩谷与老林相连", "kind": "rock_pass", "tier": "late", "width": 4.8,
             "path": [[46, -40], [35, -35], [27, -30], [19, -39]]},
            {"id": "east_coast_link", "label": "东岸林隙与湿地高岸", "kind": "forest_gap", "tier": "late", "width": 3.4,
             "path": [[75, -37], [84, -20], [94, -5], [85, 9], [70, 17], [57, 21], [43, 25], [28, 27]]},
            {"id": "wetland_wood_link", "label": "湿地高岸补给线", "kind": "forest_gap", "tier": "mid", "width": 3.6,
             "path": [[57, 21], [63, 33], [70, 40], [60, 54]]},
            {"id": "south_coast_link", "label": "南岸树林深处支线", "kind": "forest_gap", "tier": "mid", "width": 3.4,
             "path": [[-69, 57], [-63, 69], [-53, 79], [-41, 81], [-28, 70]]},
        ]
    routes = [{"id": r["id"], "label": r["label"], "tier": r["tier"], "width": r.get("width", 7 if r["kind"] == "primary" else 5),
               "world": curve(r["path"]), "kind": r["kind"], "surface": "natural_ground"} for r in route_defs]
    waterways = [{**r, "path": curve(r["path"])} for r in prototype["waterways"]]
    # Finish both watercourses at the shoreline instead of inland dead ends.
    waterways[0]["path"] = curve(prototype["waterways"][0]["path"] + [[73, 80], [76, 87]])
    waterways[1]["path"] = curve(prototype["waterways"][1]["path"] + [[-95, 65]])
    river_segments = []
    for index, river in enumerate(waterways):
        pieces = segments(river["path"])
        total = sum(math.dist(a, b) for a, b in pieces)
        before = 0.0
        for a, b in pieces:
            length = math.dist(a, b)
            river_segments.append((index, a, b, length, before, total))
            before += length
    clearings = camps + stepping_sites + extraction + [dict(g, extent=[g["radius"] + 1, g["radius"] + 1]) for g in gold]
    # A broken coastal shelf shelters the first clearing; it has no rectangular wall.
    coastal_shelf = curve([[-102, -55], [-94, -53], [-83, -53], [-77, -49]])

    def clearing_radius(angle, c):
        phase = sum(ord(v) for v in c["id"]) * .17
        return 1 + .10 * math.sin(angle * 3 + phase) + .06 * math.cos(angle * 5 - phase)

    def clearing_distance(x, z, c):
        dx, dz = (x - c["world"][0]) / c["extent"][0], (z - c["world"][1]) / c["extent"][1]
        radius = math.hypot(dx, dz)
        if revision == 1:
            return radius
        angle = math.atan2(dz, dx)
        return radius / clearing_radius(angle, c)

    if revision >= 2:
        for c in camps:
            c["polygon"] = curve([
                [c["world"][0] + c["extent"][0] * math.cos(a) * clearing_radius(a, c),
                 c["world"][1] + c["extent"][1] * math.sin(a) * clearing_radius(a, c)]
                for a in [i * math.tau / 12 for i in range(12)]
            ], True)

    def river_profile(x, z):
        best = None
        for index, a, b, length, before, total in river_segments:
            dx, dz = b[0] - a[0], b[1] - a[1]
            t = max(0, min(1, ((x - a[0]) * dx + (z - a[1]) * dz) / (length * length))) if length else 0
            distance = math.hypot(x - a[0] - t * dx, z - a[1] - t * dz)
            if best is not None and distance > best[0] + 2.5: continue
            progress = (before + t * length) / total
            width = (2.1 if index == 0 else 1.65) + .48 * math.sin(progress * 18 + index) + .28 * math.sin(progress * 37 + .7)
            width += .7 * smooth(.65, .94, progress)
            level = 1.62 - 1.07 * smooth(.73, 1, progress)
            if best is None or distance - width < best[0] - best[1]: best = (distance, width, level)
        return best

    def carve_river(x, z, height):
        distance, width, level = river_profile(x, z)
        if distance < width + 2.5:
            bed_weight = 1 - smooth(width * .28, width + 2.5, distance)
            depth = .30 + .09 * math.sin(x * .12 + z * .10)
            height = height * (1 - bed_weight) + (level - depth) * bed_weight
        return height, level if distance < width + 4 else SEA

    def fields(x, z):
        shore = polygon_distance(x, z, coast)
        route = min(line_distance(x, z, r["world"]) - r["width"] / 2 for r in routes)
        ridge = max(polygon_distance(x, z, r["polygon"]) for r in ridges)
        forest = max(polygon_distance(x + 1.2 * math.sin(z * .23), z + 1.1 * math.sin(x * .19), f["polygon"]) for f in forests)
        wetland = polygon_distance(x, z, marsh)
        channel = min(line_distance(x, z, r["path"]) for r in waterways)
        clearing = min(clearing_distance(x, z, c) for c in clearings)
        return shore, route, ridge, forest, wetland, channel, clearing

    def terrain(x, z, field, with_river=True):
        shore, route, ridge, forest, wetland, channel, clearing = field
        base = 1.95 + .09 * math.sin(x * .067 + z * .031) + .07 * math.cos(z * .083 - x * .025)
        height = base + (3.5 * smooth(-2.5, 3.8, ridge) if revision >= 3 else 5.8 * smooth(-5, 11, ridge))
        height += 3.1 * (1 - smooth(1.8, 5.8, line_distance(x, z, coastal_shelf)))
        # Footpaths and mountain passes are a continuous natural saddle, not a road material.
        saddle = 1 - smooth(0, 4, route)
        height = height * (1 - saddle) + base * saddle
        clearing_weight = 1 - smooth(.82, 1.35, clearing)
        height = height * (1 - clearing_weight) + 1.95 * clearing_weight
        if wetland > -4:
            pool = max(0, math.sin(x * .13 + z * .09) * math.cos(z * .14 - x * .04))
            target = 1.54 - .57 * pool
            bog_weight = smooth(-4, 4, wetland) * smooth(0, 3, route) * smooth(.9, 1.5, clearing)
            height = height * (1 - bog_weight) + target * bog_weight
        level = -100
        # Shallow freshwater channels are wadeable; dry banks stay buildable.
        if revision >= 3:
            if with_river: height, level = carve_river(x, z, height)
        elif channel < 3.5 and clearing > 1.12:
            stream_level = 1.62 if z < 50 else 1.62 - min(.98, (z - 50) * .027)
            if wetland > 0 and shore > 7: stream_level = max(1.52, stream_level)
            bed_weight = 1 - smooth(.8, 3.5, channel)
            height = height * (1 - bed_weight) + (stream_level - .32) * bed_weight
            level = stream_level
        if wetland > 0 and height < 1.61:
            level = max(level, 1.52)
        if shore < 7:
            coastal_height = SEA + shore * .23
            height = min(height, coastal_height) if shore < 0 else height * smooth(0, 7, shore) + coastal_height * (1 - smooth(0, 7, shore))
            level = max(SEA, level) if shore < 3 else level
        height = max(-3.7, height)
        tile = 4 if shore < 6 else 5 if ridge > (-.3 if revision >= 3 else -2) and route > 2 and clearing > 1.2 else 3 if wetland > 0 else 7 if forest > -6 else 6
        return round(height, 5), round(level, 5), tile

    heights, water, tiles, dry_heights = [], [], [], []
    for row in range(SIDE + 1):
        for col in range(SIDE + 1):
            x, z = col * 2 - 128, row * 2 - 128
            f = fields(x, z)
            h, level, tile = terrain(x, z, f)
            if revision >= 3: dry_heights.append(terrain(x, z, f, False)[0])
            heights.append(h)
            water.append(level)
            tiles.append(tile)

    surface_heights, surface_water, surface_shore = [], [], []
    if revision >= 3:
        for row in range(257):
            for col in range(257):
                ix, iz = min(col // 2, 127), min(row // 2, 127)
                u, v = col * .5 - ix, row * .5 - iz
                a, b = dry_heights[iz * 129 + ix:iz * 129 + ix + 2]
                c, d = dry_heights[(iz + 1) * 129 + ix:(iz + 1) * 129 + ix + 2]
                dry = (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
                x, z = col - 128, row - 128
                h, level = carve_river(x, z, dry)
                shore = polygon_distance(x, z, coast)
                if inside(x, z, marsh) and h < 1.61: level = max(level, 1.52)
                # The river joins the sea continuously at both mouths.
                if shore < 7:
                    blend = smooth(0, 7, shore)
                    level = SEA + (level - SEA) * blend
                surface_heights.append(round(h, 5))
                surface_water.append(round(level, 5))
                surface_shore.append(round((level - h) * 3, 5))
        for row in range(129):
            for col in range(129):
                heights[row * 129 + col] = surface_heights[row * 2 * 257 + col * 2]
                water[row * 129 + col] = surface_water[row * 2 * 257 + col * 2]

    potential, buildable, trees, hard_land, field_by_cell = set(), set(), set(), set(), {}
    for row in range(SIDE):
        for col in range(SIDE):
            cell = (col, row)
            x, z = world_at(cell)
            f = fields(x, z)
            field_by_cell[cell] = f
            corners = [surface_heights[(row * 2 + dz) * 257 + col * 2 + dx] for dz in (0, 1, 2) for dx in (0, 1, 2)] if revision >= 3 else [heights[(row + dz) * 129 + col + dx] for dz in (0, 1) for dx in (0, 1)]
            levels = [surface_water[(row * 2 + dz) * 257 + col * 2 + dx] for dz in (0, 1, 2) for dx in (0, 1, 2)] if revision >= 3 else [water[(row + dz) * 129 + col + dx] for dz in (0, 1) for dx in (0, 1)]
            low, high, level = min(corners), max(corners), max(levels)
            max_depth = max(w - h for h, w in zip(corners, levels)) if revision >= 3 else level - low
            relief = high - low
            # Dry elevated plateaus are also rock barriers, with visible silhouettes.
            relief_limit = .95 if f[5] < 4 else .62
            coastal_shallow = low > SEA - .12 or revision >= 3 and f[5] < 6
            allowed = f[0] > .5 and coastal_shallow and relief < relief_limit and (revision >= 3 or high < 4.0) and max_depth < .48
            if not allowed:
                # Surf is already a visible boundary. Never ring the beach in a stone wall.
                if f[0] > 6 and low > level + .08: hard_land.add(cell)
                continue
            potential.add(cell)
            if max_depth < -.14 and relief < .34 and low > 1.04:
                buildable.add(cell)
                # Interlocking groves have dense resource cores and open understory.
                noise = 2.8 * math.sin(x * .089 + z * .053) + 2 * math.cos(z * .103 - x * .043)
                wooded = f[3] + noise > (-25 if revision >= 2 else -16)
                secondary = math.sin(x * .083 + math.sin(z * .067)) * math.cos(z * .092) > (.16 if revision >= 2 else .30)
                wooded |= secondary and f[0] > 14 and f[2] < -5 and f[4] < -6 and abs(x) > 25
                if revision >= 2:
                    clumps = math.sin(x * .31 + math.sin(z * .11) * 1.2) + .7 * math.cos(z * .27 - x * .08) + .35 * math.sin(x * .49 + z * .32)
                    wooded &= clumps < (1.42 if f[3] > 4 else 1.15)
                if revision >= 3 and any(math.dist((x, z), c["world"]) < 26 for c in rock_refuges):
                    wooded |= clumps < 1.4
                if wooded and f[1] > (.2 if revision >= 2 else 1.0) and f[6] > 1.18 and f[0] > 7 and f[5] > 4:
                    trees.add(cell)

    origin = cell_at(spawns[0]["world"])
    # Land outside the explorable component gets visible rock/sea cues, not invisible lawns.
    connected_land = flood(potential, origin)
    hard_land |= potential - connected_land
    potential = connected_land
    trees &= potential
    buildable &= potential
    if revision >= 3 and len(trees) > 2950:
        # Keep a similar finite wood reserve while adding woodland to rock valleys.
        # Thin low-density margins first; thick clumps remain useful barriers.
        ranked = sorted(trees, key=lambda c: (field_by_cell[c][3] + 4 * math.sin(world_at(c)[0] * .19 + world_at(c)[1] * .13), c))
        trees -= set(ranked[:len(trees) - 2950])
    reachable = flood(potential - trees, origin)
    pocket_links = []
    if revision >= 3:
        # Join open understory pockets instead of filling them back in with trees.
        # Route through flat harvestable land, never through permanent rock or sea.
        pending = potential - trees - reachable
        while pending:
            component = flood(pending, min(pending))
            pending -= component
            if len(component) < 4: continue
            frontier = [(0, c) for c in component]
            heapq.heapify(frontier)
            costs = {c: 0 for c in component}
            parents, destination = {}, None
            while frontier:
                cost, cell = heapq.heappop(frontier)
                if cost != costs[cell]: continue
                if cell in reachable:
                    destination = cell
                    break
                x, y = cell
                for neighbour in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if neighbour not in potential: continue
                    next_cost = cost + (8 if neighbour in trees else 1)
                    if next_cost < costs.get(neighbour, math.inf):
                        costs[neighbour], parents[neighbour] = next_cost, cell
                        heapq.heappush(frontier, (next_cost, neighbour))
            assert destination is not None, "An understory pocket lacks a route through usable land"
            path = [destination]
            while path[-1] in parents: path.append(parents[path[-1]])
            trees -= set(path)
            if len(path) > 2:
                pocket_links.append({"id": f"understory_link_{len(pocket_links) + 1}", "label": "树群间自然开口", "kind": "understory_link", "tier": "mid", "width": 2,
                                     "world": [list(world_at(c)) for c in path], "surface": "natural_ground"})
            reachable = flood(potential - trees, origin)
            pending -= reachable
        routes += pocket_links
    # Keep only connected gaps open; enclosed small pockets stay visibly wooded.
    stranded = potential - trees - reachable
    trees |= stranded & buildable
    hard_land |= stranded - buildable
    potential -= stranded - buildable
    buildable -= hard_land

    for c in clearings:
        assert cell_at(c["world"]) in reachable, f"Unreachable clearing: {c['id']}"
    for r in routes:
        for p in r["world"]:
            cell = cell_at(p)
            if cell not in reachable:
                col, row = cell
                corners = [heights[(row + dz) * 129 + col + dx] for dz in (0, 1) for dx in (0, 1)]
                levels = [water[(row + dz) * 129 + col + dx] for dz in (0, 1) for dx in (0, 1)]
                raise AssertionError(f"Unreachable route {r['id']}: {p}; field={field_by_cell[cell]}; heights={corners}; water={levels}; potential={cell in potential}; tree={cell in trees}")

    # Record interior approaches for body-clearance checks in the live runtime.
    forest_entrances = []
    if revision >= 2:
        for route in routes:
            if route["kind"] != "forest_gap": continue
            candidates = []
            for p in route["world"]:
                cell = cell_at(p)
                col, row = cell
                adjacent_trees = sum(n in trees for n in ((col - 1, row), (col + 1, row), (col, row - 1), (col, row + 1)))
                if cell in reachable and adjacent_trees and field_by_cell[cell][6] > 1.25:
                    candidates.append((adjacent_trees, cell))
            assert candidates, f"Forest route lacks a wooded narrow approach: {route['id']}"
            _, center = max(candidates)
            forest_entrances.append({"route": route["id"], "world": list(world_at(center)), "kind": "forest_gap"})

    placements = []
    for col, row in sorted(trees, key=lambda c: (c[1], c[0])):
        x, z = world_at((col, row))
        # Jitter stays inside the authored collision cell, while canopy sizes vary.
        scale = round(rng.uniform(.72, 1.23), 3)
        placements.append(["broadleaf", round(x + rng.uniform(-.67, .67), 4), round(z + rng.uniform(-.67, .67), 4),
                           round(rng.uniform(-math.pi, math.pi), 4), scale, round(scale * rng.uniform(.92, 1.08), 3), 20])
    # Scatter defensive rocks along forest edges and camp approaches. Keep
    # isolated hard-land cells sparse so rock reads as a usable barrier rather
    # than a solid quarry that erases buildable space.
    rock_candidates = set()
    for col, row in hard_land:
        neighbours = {(col - 1, row), (col + 1, row), (col, row - 1), (col, row + 1)}
        near_camp = any(math.dist(world_at((col, row)), c["world"]) < 24 for c in camps)
        forest_edge = any(n in trees for n in neighbours)
        open_edge = any(n in reachable and n not in trees for n in neighbours)
        if (near_camp and (forest_edge or open_edge)) or (forest_edge and open_edge):
            rock_candidates.add((col, row))
    # Deterministic thinning leaves short, interrupted defensive lines.
    for col, row in sorted(rock_candidates, key=lambda c: (c[1], c[0])):
        boundary = any(n in reachable or n in trees for n in ((col - 1, row), (col + 1, row), (col, row - 1), (col, row + 1)))
        hollow_edge = revision >= 2 and any(clearing_distance(*world_at((col, row)), c) < 1.7 for c in rock_refuges)
        if rng.random() > (.52 if near_camp else .34): continue
        x, z = world_at((col, row))
        scale = round(rng.uniform(1.0, 1.5), 3)
        placements.append(["rock", x, z, round(rng.uniform(-math.pi, math.pi), 4), scale, scale])
    walk = [int((col, row) in reachable) for row in range(SIDE) for col in range(SIDE)]
    build = [int((col, row) in reachable and (col, row) in buildable) for row in range(SIDE) for col in range(SIDE)]
    local = {c["id"]: 20 * sum(math.dist(world_at(t), c["world"]) <= 30 for t in trees) for c in camps}
    camp_plots = {c["id"]: sum(clearing_distance(*world_at(t), c) < .85 for t in reachable & buildable) for c in camps}
    forest_metrics = []
    for f in forests:
        land = {c for c in potential if inside(*world_at(c), f["polygon"])}
        core = {c for c in land if polygon_distance(*world_at(c), f["polygon"]) > 8}
        forest_metrics.append({"id": f["id"], "label": f["label"], "land_cells": len(land),
                               "tree_cells": len(land & trees), "interior_open_cells": len(core & reachable),
                               "wood": len(land & trees) * 20})
    metrics = {"harvestable_trees": len(trees), "total_wood": len(trees) * 20, "wood_per_tree": 20,
               "wood_within_30m_per_site": local, "buildable_cells_per_site": camp_plots, "open_walkable_cells": sum(walk), "open_buildable_cells": sum(build),
               "land_after_harvesting_cells": len(potential), "unreachable_open_cells": 0,
               "visible_rock_placements": sum(p[0] == "rock" for p in placements), "gold_reserve": sum(g["reserve_gold"] for g in gold)}
    if revision >= 2:
        metrics["forest_regions"] = forest_metrics
        metrics["interior_camps"] = len(forest_sites)
        metrics["rock_hollows"] = len(rock_refuges)
    assert len(trees) >= (2700 if revision >= 3 else 2800), metrics
    assert all(local[c["id"]] >= (2400 if revision >= 3 and c.get("kind") == "rock_hollow" else 1000 if c.get("kind") == "rock_hollow" else 2000) for c in camps), metrics
    assert min(camp_plots.values()) >= (24 if revision >= 2 else 45), metrics
    assert sum(build) >= 1600, metrics
    biome_regions = [{"biome": "swamp", "polygon": marsh}]
    biome_regions += [{"biome": "mountain", "polygon": r["polygon"]} for r in ridges]
    biome_regions += [{"biome": "rainforest", "polygon": f["polygon"]} for f in forests]
    layout = {"id": map_id, "side": SIDE, "opening_overlay": False, "free_fossil_placement": True, "region_profile": "authored",
              "spawn_points": spawns, "extraction_sites": extraction, "camp_sites": camps, "gold_zones": gold, "routes": routes,
              "heights": heights, "water": water, "tiles": tiles, "walk": walk, "build": build, "placements": placements}
    if revision >= 3:
        layout["surface_heights"] = surface_heights
        layout["surface_water_levels"] = surface_water
        layout["surface_shore_field"] = surface_shore
        layout["stepping_sites"] = stepping_sites
        metrics["connected_pocket_links"] = len(pocket_links)
        metrics["hard_rock_cells"] = len(hard_land)
        metrics["stepping_sites"] = len(stepping_sites)
    design = {"schema": "jurassic-park.map-design/v2", "id": map_id, "name": "原始荒岛", "status": "playable-review",
              "approved_prototype": "res://data/map_candidates/organic_island_prototype_v1.json", "seed": SEED,
              "runtime": f"res://data/maps/organic_island_v{revision}.json", "metrics": metrics, "spawn_points": spawns,
              "extraction_sites": extraction, "camp_sites": camps, "gold_zones": gold, "routes": routes,
              "coastline": coast, "waterways": waterways, "biome_regions": biome_regions, "default_biome": "rainforest",
              "rules": ["全部树木可采，每棵20木且不可再生；保留厚林可抵挡恐龙，砍穿后必须补防。",
                        "单人和合作从满足木材、平地与空间条件的生存区域随机开始，没有四方阵营或人工道路网。",
                        "登陆林地与迁营台地平缓可建，树木格采完后可以通行和建造。",
                        "浅溪与湿地浅水允许涉水；海水、陡崖和实体岩石提供清晰不可达边界。",
                        "化石挖掘场可在任何适合建造的平坦地面建造，不受地图矿点限制。"],
              "review_limits": "通行、资源和建造配置经过专项检查；长局维修消耗、恐龙压力和合作体验需试玩确认。"}
    if revision >= 2:
        design["forest_entrances"] = forest_entrances
        design["rules"][1:3] = [
            "大块森林由厚树丛、弯曲林隙和不规则林中空地构成，可在采伐前进入内部并建营。",
            "林中窄缝允许幸存者通行，厚林和岩肩护住侧翼；小型恐龙仍可进入，营地需要防守。",
            "岩石围合的是可建谷底，不是整块禁入山体；可见裂口连接外部探索区。",
            "所有干燥平缓的林下空地均可建造，不限于标出的营地；采伐可以继续扩建。",
        ]
    if revision >= 3:
        design["stepping_sites"] = stepping_sites
        design["rules"] += ["小型林下空隙通过自然开口连接主探索区，不把断开的空隙重新填成厚林。",
                             "岩脊缩成局部岩肩，与补给林隙和谷底交错；岩谷30米内至少2400木材。",
                             "河道有变化的宽度、浅滩和连续岸线，渲染、碰撞和水深共用一米地表数据。"]
    return layout, design


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", type=int, choices=(1, 2, 3), default=3)
    args = parser.parse_args()
    layout, design = build_map(args.version)
    for relative, value, compact in [(f"data/maps/organic_island_v{args.version}.json", layout, True),
                                     (f"data/map_candidates/organic_island_v{args.version}.json", design, False)]:
        target = ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(value, ensure_ascii=False, indent=None if compact else 2,
                          separators=(",", ":") if compact else None) + "\n", encoding="utf-8")
    print(json.dumps(design["metrics"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
