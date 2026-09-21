"""Read map geometry/placement data only; never execute JASS or import Warcraft art.
Outputs derived layout for the original Godot blockout meshes. Run from any cwd.
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / 'reference/warcraft-6.5'
b = (REF / 'war3map.w3e').read_bytes()
assert b[:4] == b'W3E!'
w, h = struct.unpack_from('<II', b, 65)
assert (w, h) == (129, 129) and len(b) == 81 + w*h*7
vertices = [struct.unpack_from('<HHBBB', b, 81+i*7) for i in range(w*h)]
heights = []
tiles = []
water = []
for row in range(h):
    for x in range(w):
        g, wh, flags, var, cliff = vertices[(h-1-row)*w+x]
        heights.append(round(((g-8192)/4 + ((cliff & 15)-2)*128)/64, 5))
        tiles.append(flags & 15)
        water.append(round(((wh & 0x3fff)-8192)/256, 5) if flags & 0x40 else -100)
p = (REF / 'war3map.wpm').read_bytes()
assert p[:4] == b'MP3W' and struct.unpack_from('<II', p, 8) == (512, 512)
walk, build = [], []
for row in range(128):
    for x in range(128):
        # Navigation uses a 128-cell grid. Require the four central subcells;
        # footprint fidelity and subcell-sized gaps remain a later pathing task.
        flags = [p[16+(511-(row*4+dy))*512+x*4+dx] for dy in (1,2) for dx in (1,2)]
        walk.append(int(not any(f & 2 for f in flags)))
        build.append(int(not any(f & 10 for f in flags)))
# Doodad placement v8/subversion11; preserve original XY and model transforms.
b = (REF / 'war3map.doo').read_bytes()
assert b[:4] == b'W3do' and struct.unpack_from('<II', b, 4) == (8,11)
pos = 16
placements = []
counts = {}
for _ in range(struct.unpack_from('<I', b, 12)[0]):
    kind = b[pos:pos+4].decode('ascii')
    variation, x, y, z, angle, sx, sy, sz = struct.unpack_from('<I7f', b, pos+4)
    pos += 36
    flags, life, table, sets = struct.unpack_from('<BBII', b, pos)
    pos += 10
    for __ in range(sets):
        count = struct.unpack_from('<I', b, pos)[0]
        pos += 4+8*count
    pos += 4
    model = ''
    if kind in ('ZTtw','ZTtc','NTtw','WTst','BTtc','ATtr','BTtw','YTpc','APct'):
        model = 'snow_tree' if kind in ('WTst','NTtw') else 'broadleaf'
    elif kind in ('ZRrk','ARrk','IRrs','IRrk','DRrk','LRrk','CRrk','NRrk','ZRrs'):
        model = 'rock'
    if model and flags != 0 and life > 0:
        placements.append([model, round(x/64,5), round(-y/64,5), round(angle,5), round(sx,4), round(sz,4)])
        counts[model] = counts.get(model,0)+1
out = ROOT / 'godot/data/terrain.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(dict(side=128, heights=heights, tiles=tiles, water=water, walk=walk, build=build, placements=placements), separators=(',',':')))
print(f'Imported {len(heights)} vertices, {sum(walk)} traversable cells, placements: {counts}')
