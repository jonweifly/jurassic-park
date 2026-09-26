"""Original seamless 4m ground surfaces: colour + physical relief in alpha.
Run .tools/art-venv/bin/python art/scripts/build_ground_surfaces.py.
No external imagery; deterministic periodic noise, grass, litter and stones.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[2] / 'godot/assets/materials/terrain'
OUT.mkdir(parents=True, exist_ok=True)
N = 1024
rng = np.random.default_rng(650925)


def noise(cells):
    field = rng.random((cells, cells))
    coord = np.arange(N) * cells / N
    i = coord.astype(int)
    f = coord - i
    f = f*f*(3-2*f)
    a = field[i[:, None], i[None, :]]
    b = field[i[:, None], (i[None, :]+1) % cells]
    c = field[(i[:, None]+1) % cells, i[None, :]]
    d = field[(i[:, None]+1) % cells, (i[None, :]+1) % cells]
    return (a*(1-f)[None, :]+b*f[None, :])*(1-f)[:, None] + (c*(1-f)[None, :]+d*f[None, :])*f[:, None]


def build(kind):
    macro = noise(4)*.5+noise(11)*.3+noise(37)*.2
    grains = noise(128)*.7+rng.random((N, N))*.3
    soil = np.array([103, 86, 63])
    height = .29 + macro*.22 + grains*.10
    rgb = soil[None, None, :]*(.64+macro[..., None]*.67+grains[..., None]*.20)
    if kind == 'turf':
        growth = np.clip((macro-.27)*2.8, 0, 1)
        green = np.array([70, 87, 42])[None, None, :]*(.65+grains[..., None]*.60)
        rgb = rgb*(1-growth[..., None])+green*growth[..., None]
    elif kind == 'litter':
        rgb *= np.array([.72, .76, .68])
    elif kind == 'rock':
        rgb = np.array([113, 111, 95])[None, None, :]*(.58+macro[..., None]*.72+grains[..., None]*.20)
    color = Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), 'RGB')
    relief = Image.fromarray(np.uint8(np.clip(height*255, 0, 255)), 'L')
    draw, bump = ImageDraw.Draw(color), ImageDraw.Draw(relief)

    def poly(points, col, h):
        # Wrap every surface feature, not just noise, so no seam is introduced.
        for dy in (-N, 0, N):
            for dx in (-N, 0, N):
                shifted = [(float(x+dx), float(y+dy)) for x, y in points]
                if max(x for x, y in shifted) < 0 or min(x for x, y in shifted) >= N or max(y for x, y in shifted) < 0 or min(y for x, y in shifted) >= N:
                    continue
                draw.polygon(shifted, fill=tuple(int(v) for v in col))
                bump.polygon(shifted, fill=int(h))

    # Different stone sizes, irregular outlines and facets give soil real structure.
    count = 1250 if kind == 'rock' else 480
    for _ in range(count):
        center = rng.uniform(0, N, 2)
        radius = rng.uniform(3, 17 if kind == 'rock' else 7)
        angles = np.arange(7)*np.pi*2/7
        pts = center + np.stack([np.cos(angles), np.sin(angles)], axis=1)*rng.uniform(.6, 1.2, (7, 1))*radius
        stone = np.array([110, 104, 87])*rng.uniform(.67, 1.2)
        poly(pts, stone*.66, 101)
        poly(center+(pts-center)*.80-np.array([.3, .5]), stone, rng.integers(138, 170))
        poly([pts[0], pts[1], center, pts[-1]], stone*.84, 128)

    if kind == 'turf':
        # Clusters of bent blades; broad bare patches keep the soil readable.
        for _ in range(31000):
            x, y = rng.uniform(0, N, 2)
            density = float(growth[int(y), int(x)])
            if rng.random() > density*.94: continue
            angle = rng.uniform(0, np.pi*2)
            axis = np.array([np.cos(angle), np.sin(angle)])
            side = np.array([-axis[1], axis[0]])
            length = rng.uniform(5, 22)
            base = np.array([x, y])
            tip = base+axis*length+side*rng.uniform(-4, 4)
            mid = base+axis*length*.48
            tint = np.array([86, 104, 48]) * rng.uniform(.56, 1.28)
            if rng.random() < .12: tint = np.array([117, 102, 65])*rng.uniform(.75, 1.1)
            pts = [base-side*.6, mid-side*1.2, tip, mid+side*1.0, base+side*.6]
            poly(pts, tint, rng.integers(140, 175))
    if kind in ('litter', 'soil', 'turf'):
        for _ in range(950 if kind == 'litter' else 75):
            base = rng.uniform(0, N, 2)
            angle = rng.uniform(0, np.pi*2)
            axis = np.array([np.cos(angle), np.sin(angle)])
            side = np.array([-axis[1], axis[0]])
            length = rng.uniform(10, 32)
            width = length*rng.uniform(.22, .35)
            pts = [base-axis*length*.5, base-axis*length*.2+side*width, base+axis*length*.24+side*width*.7, base+axis*length*.55, base+axis*length*.15-side*width*.65, base-axis*length*.25-side*width*.7]
            tint = np.array([[91, 69, 41], [121, 90, 49], [84, 83, 47], [135, 112, 67]])[rng.integers(4)]*rng.uniform(.65, 1.1)
            poly(np.array(pts)*1.0+np.array([1, 1]), tint*.5, 105)
            poly(pts, tint, 156)
            poly([pts[0], pts[1], pts[2], pts[3]], tint*1.14, 168)
            poly([base-axis*length*.45, base+axis*length*.5, base+side*.7], tint*.65, 146)
    color.putalpha(relief)
    color.save(OUT / f'{kind}.png', optimize=True)
    print('Ground surface:', kind, flush=True)


for kind in ['turf', 'soil', 'litter', 'rock']:
    build(kind)
