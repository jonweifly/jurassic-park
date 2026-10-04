"""Annotate the Godot overview (or a simple terrain plot) using baked map data.

Requires Pillow. --capture uses capture_organic_island.gd's square 275m view.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/map_candidates"
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--version", type=int, choices=(1, 2, 3), default=3)
    args = parser.parse_args()
    prefix = f"organic_island_v{args.version}"
    layout = json.loads((ROOT / f"data/maps/{prefix}.json").read_text())
    spec = json.loads((OUT / f"{prefix}.json").read_text())
    m = spec["metrics"]
    canvas = Image.new("RGB", (1700, 1240), "#102b2d")
    draw = ImageDraw.Draw(canvas)

    def txt(x, y, value, size=22, color="#e7edda"):
        draw.text((x, y), value, fill=color, font=ImageFont.truetype(FONT, size))

    txt(40, 24, "原始荒岛", 44)
    txt(270, 47, f"GODOT 试玩版 V{args.version} · 可深入的森林与岩抱谷", 24, "#adc8b6")
    txt(40, 95, f"{m['harvestable_trees']:,} 棵可采树 / {m['total_wood']:,} 木材    ·    林间空地与围合谷底    ·    溪流与湿地可以涉水", 21, "#e6ca87")
    size, ox, oy = 1050, 40, 153
    span = 256

    def project(point):
        return ox + (point[0] / span + .5) * size, oy + (point[1] / span + .5) * size

    if args.capture:
        capture = Image.open(OUT / f"{prefix}_overview.png").convert("RGB")
        # The 275m capture includes sky beyond the 256m terrain mesh; crop it
        # at world bounds while preserving marker projection from runtime data.
        margin = capture.width * (275 - span) / 550
        base = capture.resize((size, size), Image.Resampling.LANCZOS,
                              box=(margin, margin, capture.width - margin, capture.height - margin))
    else:
        base = Image.new("RGB", (128, 128), "#184857")
        ink = ImageDraw.Draw(base)
        trees = {tuple(int((p[i] + 128) // 2) for i in (1, 2)) for p in layout["placements"] if p[0] == "broadleaf"}
        for y in range(128):
            for x in range(128):
                i = y * 128 + x
                h = layout["heights"][y * 129 + x]
                tile = layout["tiles"][y * 129 + x]
                color = "#184857" if h < .8 else "#b1a679" if tile == 4 else "#777c72" if tile == 5 else "#728a5e"
                if layout["water"][y * 129 + x] > h: color = "#54969b" if h > .8 else "#184857"
                if (x, y) in trees: color = "#284f33"
                ink.point((x, y), fill=color)
        base = base.resize((size, size), Image.Resampling.NEAREST)
    canvas.paste(base, (ox, oy))
    draw = ImageDraw.Draw(canvas)
    for route in spec["routes"]:
        points = [project(p) for p in route["world"]]
        # Fine dashed traces indicate exploration, never a paved road texture.
        for index, (a, b) in enumerate(zip(points, points[1:])):
            if index % 2 == 0: draw.line((a, b), fill="#b3cca8" if route["kind"] == "forest_gap" else "#d8c395", width=2)

    def label(point, value, color="#efe7b9", offset=(10, -18)):
        x, y = project(point)
        font = ImageFont.truetype(FONT, 18)
        bounds = draw.textbbox((x + offset[0], y + offset[1]), value, font=font)
        draw.rounded_rectangle((bounds[0] - 5, bounds[1] - 3, bounds[2] + 5, bounds[3] + 3), 4, fill="#16342d")
        draw.text((x + offset[0], y + offset[1]), value, fill=color, font=font)

    for index, site in enumerate(spec["camp_sites"]):
        x, y = project(site["world"])
        color = "#bac2c7" if site.get("kind") == "rock_hollow" else "#d7eab5"
        if site.get("polygon"):
            draw.line([project(p) for p in site["polygon"] + site["polygon"][:1]], fill=color, width=2)
        draw.ellipse((x - 9, y - 9, x + 9, y + 9), fill=color, outline="#122c20", width=2)
        name = "登陆" if index == 0 else "岩谷" if site.get("kind") == "rock_hollow" else "林中" if site.get("kind") == "forest_interior" else "林缘"
        label(site["world"], name, offset=(12, -32) if site.get("kind") == "rock_hollow" else (12, 3))
    for zone in spec["gold_zones"]:
        x, y = project(zone["world"])
        draw.polygon([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)], fill="#efd05d", outline="#3b2c15")
        label(zone["world"], f"{zone['reserve_gold']} 金", "#efd05d", offset=(12, -24))
    rescue = spec["extraction_sites"][0]["world"]
    x, y = project(rescue)
    draw.rectangle((x - 9, y - 9, x + 9, y + 9), fill="#dbeadb", outline="#1b3d2f", width=2)
    label(rescue, "H 救援", offset=(-85, 8))
    for point, value in [([-12, -71], "北侧山脊"), ([40, -25], "东侧岩脊"), ([-95, 25], "西南断崖"),
                         ([52, 49], "浅水湿地"), ([-57, -79], "原始密林"), ([-47, 22], "支流")]:
        label(point, value, "#cddcce")
    txt(ox + 16, oy + 12, "N ↑", 23, "#f5edcc")
    px, py = 1124, 165
    txt(px, py, "森林可以进入、采伐、建营", 26)
    if args.capture and args.version >= 2:
        for suffix, title in [("_forest", "北林深处：厚林围着可建空地"), ("_rock_hollow", "西侧岩抱谷：东侧裂口通向谷底")]:
            txt(px, py + 54, title, 20, "#e8ce8e")
            local = Image.open(OUT / f"{prefix}{suffix}.png").convert("RGB")
            local = local.resize((530, 260), Image.Resampling.LANCZOS,
                                 box=(0, local.height * .25, local.width, local.height * .75))
            canvas.paste(local, (px, py + 89))
            py += 350
        txt(px, py + 45, "密林、林隙与林中空地交错", 24, "#e8ce8e")
        for index, line in enumerate([
            f"{m['interior_camps']} 处深林空地、2 处可进入的岩抱谷。",
            f"{m.get('stepping_sites', 0)} 处林间落脚点，岩谷旁补上木材。" if args.version >= 3 else "窄缝便于进入；小型恐龙仍可能穿行。",
            "砍树可以扩建，也会削弱天然遮挡。",
            "浅水可涉；海岸与陡崖提示不可达边界。",
            "虚线为预览标记，游戏里没有铺设道路。",
        ]):
            txt(px, py + 86 + index * 34, line, 20, "#b7cdbd")
        txt(px, 1170, "浅绿：林中空地   灰：岩谷   ◆ 金矿", 18, "#e8ce8e")
        target = OUT / f"{prefix}_preview.png"
        canvas.save(target)
        print(target)
        return
    sections = [
        ("自然孤岛", ["不规则海湾与岬角，海水直接标示边界。", "森林、岩脊与河谷形成探索分叉。", "虚线只是预览标注，游戏里没有道路网。"]),
        ("木材与天然防守", [f"全岛 {m['total_wood']:,} 木材，不可再生。", f"登陆点 30 米内 {m['wood_within_30m_per_site']['landing_grove']:,} 木。", "所有树木可采；留住厚林可以保护侧翼。", "采完的平地树格可通行、可建造。"]),
        ("可建造与探索", ["登陆点、林中落脚点和岩谷谷底都能建造。", "浅溪、沼泽浅水允许涉水，水中不可建。", "陡崖边缘有岩石轮廓，海岸没有隐形封边。", "各处空地、矿层与救援点相互可达。"]),
        ("黄金与后期路线", ["400 / 700 / 1,100 / 1,400 金矿层。", "分布在断崖、沉积岸、峡谷与深处山口。", "建化石场后才能开采，矿层库存有限。"]),
    ]
    py += 60
    for title, rows in sections:
        txt(px, py, title, 25, "#e8ce8e")
        for index, row in enumerate(rows): txt(px, py + 42 + index * 34, row, 20, "#b7cdbd")
        py += 72 + len(rows) * 34
    txt(px, 1092, "● 登陆 / 可建空地   ◆ 金矿   H 救援", 18, "#e8ce8e")
    txt(px, 1134, "深绿是木材与屏障；路线来自运行数据。", 18, "#b7cdbd")
    txt(px, 1170, "长局生存压力仍需试玩确认。", 18, "#b7cdbd")
    target = OUT / f"{prefix}_preview.png"
    canvas.save(target)
    print(target)


if __name__ == "__main__": main()
