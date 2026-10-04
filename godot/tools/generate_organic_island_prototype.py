"""Generate a low-fidelity, non-runtime layout prototype for an organic island.

The output is deliberately limited to a preview SVG and a design JSON.  It does
not touch the playable map catalog or terrain data.
"""

from __future__ import annotations

import json
from html import escape
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/map_candidates"
JSON_PATH = OUT / "organic_island_prototype_v1.json"
SVG_PATH = OUT / "organic_island_prototype_v1.svg"

CANVAS_W = 1500
CANVAS_H = 1000
MAP_X = 70
MAP_Y = 105
MAP_W = 855
MAP_H = 775
WORLD = (-130, 130, -110, 110)

COLORS = {
    "sea": "#183f4b",
    "sea_deep": "#102f3b",
    "sand": "#d6bd79",
    "land": "#9ca66e",
    "meadow": "#b9b978",
    "forest": "#285842",
    "forest_dark": "#183f32",
    "forest_edge": "#46704b",
    "mountain": "#4e5148",
    "mountain_light": "#77755b",
    "marsh": "#5d8570",
    "stream": "#55a9a4",
    "route": "#f5df9c",
    "route_secondary": "#d7efc4",
    "text": "#f5f0d2",
    "muted": "#b5cfbf",
    "panel": "#102c2b",
    "panel_line": "#3e6e64",
    "marker": "#f5c86a",
}


ISLAND = [
    (-102, -82), (-70, -96), (-28, -101), (10, -95), (47, -84),
    (76, -67), (98, -43), (94, -20), (110, -4), (103, 16),
    (86, 29), (101, 48), (91, 70), (62, 83), (35, 77),
    (12, 91), (-13, 83), (-34, 101), (-68, 90), (-89, 69),
    (-98, 45), (-115, 28), (-108, 4), (-116, -18), (-103, -37),
    (-119, -57),
]

FORESTS = [
    {
        "id": "west_old_growth",
        "label": "西侧原始森林",
        "role": "dense_natural_barrier",
        "polygon": [(-111, -43), (-91, -66), (-62, -72), (-37, -60), (-27, -40),
                    (-43, -19), (-68, -24), (-88, -8), (-108, -21)],
    },
    {
        "id": "north_canopy",
        "label": "北部高冠林",
        "role": "ridge_foot_forest",
        "polygon": [(-72, -88), (-38, -94), (-6, -78), (3, -56), (-16, -36),
                    (-47, -47), (-64, -62)],
    },
    {
        "id": "east_rainforest",
        "label": "东侧雨林",
        "role": "dense_natural_barrier",
        "polygon": [(39, -74), (70, -66), (88, -44), (72, -23), (46, -28),
                    (31, -49)],
    },
    {
        "id": "south_old_growth",
        "label": "南部低地林",
        "role": "coastal_forest",
        "polygon": [(-84, 31), (-61, 56), (-34, 73), (-10, 54), (-18, 26),
                    (-45, 15), (-67, 18)],
    },
    {
        "id": "marsh_edge_forest",
        "label": "湿地边缘林",
        "role": "soft_edge",
        "polygon": [(31, 34), (54, 22), (84, 37), (83, 63), (60, 78),
                    (34, 63)],
    },
]

MOUNTAINS = [
    {
        "id": "north_spine",
        "label": "北侧山脊",
        "role": "natural_barrier",
        "polygon": [(-28, -85), (-10, -67), (9, -60), (24, -42), (13, -20),
                    (-5, -27), (-17, -47), (-35, -60)],
    },
    {
        "id": "east_spine",
        "label": "东侧岩脊",
        "role": "natural_barrier",
        "polygon": [(37, -70), (57, -49), (63, -22), (51, 4), (35, -9),
                    (30, -34)],
    },
    {
        "id": "southwest_cliffs",
        "label": "西南断崖",
        "role": "coastal_barrier",
        "polygon": [(-92, 37), (-73, 26), (-62, 5), (-75, -10), (-103, -4),
                    (-112, 19)],
    },
]

MARSH = [
    (32, 46), (46, 31), (72, 35), (90, 54), (83, 72), (61, 78),
    (41, 68), (27, 57),
]

WATERWAYS = [
    {
        "id": "main_stream",
        "label": "主溪流",
        "role": "valley_route",
        "path": [(-5, -58), (-12, -39), (-8, -21), (2, -5), (16, 12),
                 (30, 29), (44, 48), (67, 70)],
    },
    {
        "id": "west_creek",
        "label": "西侧支流",
        "role": "coastal_access",
        "path": [(-21, 12), (-37, 22), (-51, 36), (-69, 50), (-87, 59)],
    },
]

ROUTES = [
    {
        "id": "route_landing_valley",
        "label": "登陆海湾 → 河谷",
        "tier": "early",
        "kind": "primary",
        "path": [(-102, -48), (-84, -40), (-63, -31), (-40, -20), (-18, -9),
                 (3, -2), (16, 7)],
    },
    {
        "id": "route_ridge_pass",
        "label": "北侧山口线",
        "tier": "mid",
        "kind": "secondary",
        "path": [(-18, -9), (-25, -25), (-22, -42), (-11, -54), (5, -51),
                 (19, -39)],
    },
    {
        "id": "route_creek_marsh",
        "label": "溪流 → 湿地",
        "tier": "mid",
        "kind": "primary",
        "path": [(4, -2), (16, 10), (28, 27), (43, 43), (60, 54)],
    },
    {
        "id": "route_south_coast",
        "label": "南岸林缘线",
        "tier": "early",
        "kind": "secondary",
        "path": [(-88, 59), (-69, 57), (-49, 62), (-28, 70), (-8, 70),
                 (14, 76), (35, 71)],
    },
    {
        "id": "route_east_canyon",
        "label": "东侧峡谷线",
        "tier": "late",
        "kind": "secondary",
        "path": [(16, 7), (31, -5), (48, -17), (70, -14), (92, -3)],
    },
]

MARKERS = [
    {"id": "landing_cove", "label": "可能登陆海湾", "world": [-102, -48], "kind": "landing"},
    {"id": "central_valley", "label": "中央河谷", "world": [4, -2], "kind": "valley"},
    {"id": "north_pass", "label": "北侧山口", "world": [-11, -54], "kind": "pass"},
    {"id": "marsh_edge", "label": "沼泽边缘", "world": [60, 54], "kind": "wetland"},
    {"id": "south_beach", "label": "南岸滩地", "world": [-69, 57], "kind": "coast"},
]


def sx(x: float) -> float:
    return MAP_X + (x - WORLD[0]) / (WORLD[1] - WORLD[0]) * MAP_W


def sy(z: float) -> float:
    return MAP_Y + (z - WORLD[2]) / (WORLD[3] - WORLD[2]) * MAP_H


def points(items: list[tuple[float, float]]) -> str:
    return " ".join(f"{sx(x):.1f},{sy(z):.1f}" for x, z in items)


def poly(items: list[tuple[float, float]], fill: str, stroke: str = "none", width: int = 1, opacity: float = 1.0) -> str:
    return f'<polygon points="{points(items)}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" opacity="{opacity}"/>'


def path(items: list[tuple[float, float]], stroke: str, width: int, dash: str = "", opacity: float = 1.0) -> str:
    first = items[0]
    commands = [f"M {sx(first[0]):.1f} {sy(first[1]):.1f}"]
    for x, z in items[1:]:
        commands.append(f"L {sx(x):.1f} {sy(z):.1f}")
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<path d="{" ".join(commands)}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"{dash_attr} opacity="{opacity}"/>'


def text(x: float, y: float, value: str, size: int, fill: str = COLORS["text"], weight: str = "400", anchor: str = "start") -> str:
    return f'<text x="{x}" y="{y}" fill="{fill}" font-family="Noto Sans CJK SC, PingFang SC, sans-serif" font-size="{size}px" font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>'


def world_text(x: float, z: float, value: str, size: int = 16, fill: str = COLORS["text"], weight: str = "600", anchor: str = "middle") -> str:
    return text(sx(x), sy(z), value, size, fill, weight, anchor)


def marker(item: dict) -> str:
    x, z = item["world"]
    px, py = sx(x), sy(z)
    color = COLORS["marker"]
    if item["kind"] == "landing":
        shape = f'<circle cx="{px:.1f}" cy="{py:.1f}" r="8" fill="{color}" stroke="#4c3a1e" stroke-width="2"/>'
    elif item["kind"] == "pass":
        shape = f'<polygon points="{px:.1f},{py-10:.1f} {px+9:.1f},{py+7:.1f} {px-9:.1f},{py+7:.1f}" fill="{color}" stroke="#4c3a1e" stroke-width="2"/>'
    elif item["kind"] == "wetland":
        shape = f'<rect x="{px-8:.1f}" y="{py-8:.1f}" width="16" height="16" rx="3" fill="{color}" stroke="#4c3a1e" stroke-width="2"/>'
    else:
        shape = f'<circle cx="{px:.1f}" cy="{py:.1f}" r="7" fill="{color}" stroke="#4c3a1e" stroke-width="2"/>'
    return shape + world_text(x, z + 7, item["label"], 15, COLORS["text"])


def make_design() -> dict:
    return {
        "schema": "jurassic-park.map-design/v1",
        "id": "organic-island-prototype-v1",
        "name": "原始荒岛布局原型",
        "status": "layout-prototype",
        "phase": "layout-only",
        "runtime_integration": False,
        "preview_asset": "res://data/map_candidates/organic_island_prototype_v1.svg",
        "runtime_map": None,
        "world": {
            "bounds": {"min_x": WORLD[0], "max_x": WORLD[1], "min_z": WORLD[2], "max_z": WORLD[3]},
            "coordinate_note": "原型坐标仅用于讨论布局，不代表可直接运行的 Godot 网格。",
        },
        "island_outline": {"role": "irregular_coastline", "points": ISLAND},
        "forests": FORESTS,
        "mountain_barriers": MOUNTAINS,
        "wetland": {"id": "southeast_marsh", "label": "东南潮湿低地", "role": "slow_open_area", "polygon": MARSH},
        "waterways": WATERWAYS,
        "routes": ROUTES,
        "markers": MARKERS,
        "unknown_regions": [
            {"id": "northwest_cove_interior", "label": "西北海湾内侧未知区", "reason": "后续确认是否保留可探索支线", "world": [-88, -18]},
            {"id": "eastern_headland", "label": "东侧岬角未知区", "reason": "暂不决定是否作为边缘危险区", "world": [91, -3]},
        ],
        "design_intent": [
            "岛屿轮廓由海湾、岬角、狭窄地峡和不规则海岸组成，不使用规则圆形或矩形边界。",
            "山脊集中在北部和东部，围出中央河谷，并用天然山口连接不同方向。",
            "原始森林以大块不规则斑块和林缘过渡形成屏障，不预设规则道路网。",
            "溪流从北侧山地向东南低地汇入湿地，路线沿河谷、林缘和海岸自然生成。",
            "图上没有显示的区域暂不承诺可通行；下一阶段需要把边界和碰撞一起落到 Godot。",
        ],
        "not_in_scope": [
            "木材、黄金或其他资源点配置",
            "出生点公平性与阵营布局",
            "建筑区域和建造网格",
            "精细植被、材质、碰撞和完整运行时地图",
        ],
    }


def make_svg() -> str:
    clip_id = "island-clip"
    svg: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_W}" height="{CANVAS_H}" viewBox="0 0 {CANVAS_W} {CANVAS_H}">',
        "<title>原始荒岛布局原型 V1</title>",
        "<defs>",
        f'<clipPath id="{clip_id}"><polygon points="{points(ISLAND)}"/></clipPath>',
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="5" stdDeviation="7" flood-color="#06191c" flood-opacity=".5"/></filter>',
        "</defs>",
        f'<rect width="{CANVAS_W}" height="{CANVAS_H}" fill="{COLORS["sea_deep"]}"/>',
        text(52, 48, "原始荒岛布局原型", 32, COLORS["text"], "700"),
        text(53, 79, "LOW-FIDELITY LAYOUT  /  只确认地貌、边界与自然探索方向", 15, COLORS["muted"], "500"),
        f'<rect x="{MAP_X-16}" y="{MAP_Y-16}" width="{MAP_W+32}" height="{MAP_H+32}" rx="22" fill="{COLORS["sea"]}" stroke="{COLORS["panel_line"]}" stroke-width="2" filter="url(#shadow)"/>',
        poly(ISLAND, COLORS["sand"], COLORS["sand"], 16),
        f'<g clip-path="url(#{clip_id})">',
        poly(ISLAND, COLORS["land"]),
        # Broad, irregular lowland clearings keep the map from reading as a set of zones.
        poly([(-39, -16), (-17, -29), (7, -27), (31, -9), (27, 13), (9, 24), (-21, 19), (-49, 4)], COLORS["meadow"], "none", 1, .8),
        poly([(-52, 29), (-30, 24), (-11, 35), (-16, 57), (-42, 61), (-64, 46)], COLORS["meadow"], "none", 1, .75),
        poly(MARSH, COLORS["marsh"], COLORS["forest_edge"], 2, .9),
    ]

    for mountain in MOUNTAINS:
        svg.append(poly(mountain["polygon"], COLORS["mountain"], COLORS["mountain_light"], 2, .97))
        # A few offset facets imply broken rock without becoming a finished render.
        p = mountain["polygon"]
        svg.append(poly(p[: max(3, len(p) // 2)], COLORS["mountain_light"], "none", 1, .38))

    for forest in FORESTS:
        svg.append(poly(forest["polygon"], COLORS["forest"], COLORS["forest_edge"], 2, .96))
        # Sparse canopy islands show the irregular edge and avoid a hard-edged region block.
        pxs = forest["polygon"]
        for index in range(0, len(pxs), 2):
            x, z = pxs[index]
            svg.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="13" fill="{COLORS["forest_dark"]}" opacity=".35"/>')

    for water in WATERWAYS:
        svg.append(path(water["path"], COLORS["stream"], 12, opacity=.95))
        svg.append(path(water["path"], "#9ce0c5", 3, opacity=.65))

    # Natural route traces sit above terrain but below labels and markers.
    for route in ROUTES:
        color = COLORS["route"] if route["kind"] == "primary" else COLORS["route_secondary"]
        dash = "" if route["kind"] == "primary" else "10 9"
        svg.append(path(route["path"], color, 4, dash=dash, opacity=.88))

    svg.append("</g>")
    # Coastline line is intentionally uneven and more prominent than any route.
    svg.append(poly(ISLAND, "none", "#f0d995", 3))

    # Terrain labels.
    for mountain in MOUNTAINS:
        center = mountain["polygon"][len(mountain["polygon"]) // 2]
        svg.append(world_text(center[0], center[1], mountain["label"], 15, "#f2e7bb", "600"))
    for forest in FORESTS:
        center = forest["polygon"][len(forest["polygon"]) // 2]
        svg.append(world_text(center[0], center[1], forest["label"], 15, "#d6e8c8", "600"))
    svg.append(world_text(63, 55, "东南沼泽 / 湿地", 15, "#d6e8c8", "600"))
    svg.append(world_text(19, 24, "中央开阔河谷", 15, "#f4edc8", "600"))

    for route in ROUTES:
        midpoint = route["path"][len(route["path"]) // 2]
        svg.append(world_text(midpoint[0], midpoint[1] - 5, route["label"], 12, COLORS["route"], "500"))
    for item in MARKERS:
        svg.append(marker(item))

    # North arrow and scale cue.
    svg.append(f'<path d="M {MAP_X+36} {MAP_Y+65} L {MAP_X+36} {MAP_Y+22} M {MAP_X+36} {MAP_Y+22} L {MAP_X+28} {MAP_Y+35} M {MAP_X+36} {MAP_Y+22} L {MAP_X+44} {MAP_Y+35}" stroke="{COLORS["text"]}" stroke-width="3" fill="none"/>')
    svg.append(text(MAP_X + 27, MAP_Y + 88, "N", 17, COLORS["text"], "700"))
    svg.append(path([(-104, 88), (-74, 88)], COLORS["text"], 3))
    svg.append(text(sx(-89) - 20, sy(88) + 22, "约 30 世界单位", 12, COLORS["muted"]))

    # Right-hand reading panel.
    panel_x, panel_y, panel_w, panel_h = 970, 105, 475, 775
    svg.append(f'<rect x="{panel_x}" y="{panel_y}" width="{panel_w}" height="{panel_h}" rx="18" fill="{COLORS["panel"]}" stroke="{COLORS["panel_line"]}" stroke-width="2"/>')
    svg.append(text(panel_x + 28, panel_y + 42, "这张原型先确认什么", 24, COLORS["text"], "700"))
    svg.append(text(panel_x + 28, panel_y + 70, "暂不涉及资源、建筑或运行时碰撞", 14, COLORS["muted"], "500"))

    items = [
        ("01", "岛屿轮廓", "海湾、岬角、狭窄地峡和不规则海岸线。"),
        ("02", "天然屏障", "北侧山脊、东侧岩脊、西南断崖与密林边缘。"),
        ("03", "自然水系", "溪流从山口穿过中央河谷，汇入东南湿地。"),
        ("04", "探索方向", "登陆海湾、河谷、林缘、山口和湿地形成分叉路线。"),
    ]
    y = panel_y + 120
    for number, title_value, body in items:
        svg.append(text(panel_x + 28, y, number, 15, COLORS["marker"], "700"))
        svg.append(text(panel_x + 73, y, title_value, 18, COLORS["text"], "700"))
        svg.append(text(panel_x + 73, y + 28, body, 14, COLORS["muted"], "400"))
        y += 92

    svg.append(text(panel_x + 28, y + 4, "图例", 18, COLORS["text"], "700"))
    legend = [
        (COLORS["sea"], "海水 / 岛外不可达"),
        (COLORS["sand"], "海岸带"),
        (COLORS["forest"], "原始森林 / 视觉与通行屏障"),
        (COLORS["mountain"], "山地 / 岩壁天然阻隔"),
        (COLORS["marsh"], "沼泽 / 湿地低地"),
        (COLORS["stream"], "溪流 / 低洼水系"),
    ]
    y += 34
    for color, label_value in legend:
        svg.append(f'<rect x="{panel_x+30}" y="{y-13}" width="18" height="18" rx="3" fill="{color}"/>')
        svg.append(text(panel_x + 60, y + 2, label_value, 14, COLORS["muted"]))
        y += 29

    y += 16
    svg.append(text(panel_x + 28, y, "路线线型", 18, COLORS["text"], "700"))
    svg.append(f'<line x1="{panel_x+2}" y1="{y-5}" x2="{panel_x+44}" y2="{y-5}" stroke="{COLORS["route"]}" stroke-width="4" stroke-linecap="round"/>')
    svg.append(text(panel_x + 60, y + 4, "主要探索方向", 14, COLORS["muted"]))
    svg.append(f'<line x1="{panel_x+2}" y1="{y+23}" x2="{panel_x+44}" y2="{y+23}" stroke="{COLORS["route_secondary"]}" stroke-width="4" stroke-linecap="round" stroke-dasharray="10 9"/>')
    svg.append(text(panel_x + 60, y + 32, "次要支线 / 山口线", 14, COLORS["muted"]))

    y += 76
    svg.append(f'<line x1="{panel_x+28}" y1="{y-17}" x2="{panel_x+447}" y2="{y-17}" stroke="{COLORS["panel_line"]}"/>')
    svg.append(text(panel_x + 28, y + 12, "下一步（确认后）", 18, COLORS["text"], "700"))
    svg.append(text(panel_x + 28, y + 41, "把这份布局转成 Godot 地形与明确边界，再加入", 14, COLORS["muted"]))
    svg.append(text(panel_x + 28, y + 64, "木材分布、出生点、建筑空间和碰撞测试。", 14, COLORS["muted"]))

    svg.append(text(52, 942, "原型状态：独立预览，不会改变当前可玩地图", 14, COLORS["muted"], "500"))
    svg.append(text(1445, 942, "V1  /  layout-only", 14, COLORS["muted"], "500", "end"))
    svg.append("</svg>")
    return "\n".join(svg) + "\n"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    JSON_PATH.write_text(json.dumps(make_design(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    SVG_PATH.write_text(make_svg(), encoding="utf-8")
    print(JSON_PATH)
    print(SVG_PATH)


if __name__ == "__main__":
    main()
