"""Deterministic, original tiling ground textures. Run with Python + Pillow + numpy.
No changes to gameplay terrain heights or buildability. Outputs are sRGB albedo.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'godot/assets/materials'
N = 1024
rng = np.random.default_rng(650922)

def noise(size):
    small = rng.integers(0, 256, (size, size), dtype=np.uint8)
    # Wrap borders before bicubic scaling for seamless macro colour fields.
    padded = np.pad(small, 1, mode='wrap')
    image = Image.fromarray(padded).resize(((size+2)*N//size, (size+2)*N//size), Image.Resampling.BICUBIC)
    pad = N//size
    return np.asarray(image.crop((pad, pad, pad+N, pad+N)), dtype=float)/255

def surface(name, color, litter=False):
    macro = noise(8)*.40 + noise(32)*.28 + noise(128)*.20 + rng.random((N,N))*.12
    rgb = np.array(color)[None,None,:]*(.68+macro[:,:,None]*.62)
    im = Image.fromarray(np.uint8(np.clip(rgb, 0, 255)))
    draw = ImageDraw.Draw(im)
    for _ in range(2400):
        x,y = rng.integers(0,N,2); r = int(rng.integers(1,5))
        gray = int(rng.integers(-26,25))
        c = tuple(int(np.clip(v+gray,0,255)) for v in color)
        draw.ellipse((x-r,y-r*.65,x+r,y+r*.65), fill=c)
    if litter:
        for _ in range(420):
            x,y = rng.uniform(0,N,2); length = rng.uniform(8,29); angle = rng.uniform(0,np.pi*2)
            axis = np.array([np.cos(angle),np.sin(angle)]); side=np.array([-axis[1],axis[0]])
            mid=np.array([x,y]); width=length*rng.uniform(.18,.28)
            points=[mid-axis*length*.5,mid+side*width,mid+axis*length*.5,mid-side*width]
            c=[(94,77,48),(114,94,58),(68,75,43),(131,107,66)][int(rng.integers(4))]
            draw.polygon([tuple(p) for p in points],fill=c)
            draw.line([tuple(mid-axis*length*.42),tuple(mid+axis*length*.42)],fill=(62,57,37),width=1)
    im.save(OUT / name)

surface('camp_soil.png', (114,103,78))
surface('forest_floor.png', (86,91,57), True)

# Shared actor/building atlas: retain each UV tile's original hue and layout,
# add visible grain, weave and weathering without regenerating meshes or skins.
source = np.asarray(Image.open(ROOT/'art/textures/expedition_albedo.png').convert('RGB'),dtype=float)
tile = source.shape[0]//4
for i in range(16):
    y,x=np.mgrid[:tile,:tile]; coarse=noise(16)[::4,::4][:tile,:tile]-.5
    if i in (4,13):
        grain=np.sin(x*.24+np.sin(y*.027)*2.8)+np.sin(x*.71+y*.016)*.35
        variation=grain*.065+coarse*.16
    elif i in (0,1):
        weave=((x%3==0).astype(float)+(y%3==0).astype(float)-.66)*.023
        variation=coarse*.11+weave
    elif i in (6,12,14):
        variation=coarse*.08+(rng.random((tile,tile))-.5)*.04
    else: variation=coarse*.06
    a,b=(i//4)*tile,(i%4)*tile
    source[a:a+tile,b:b+tile]*=1+variation[:,:,None]
Image.fromarray(np.uint8(np.clip(source,0,255))).save(OUT/'expedition_worn.png')
print('Authored camp_soil, forest_floor, expedition_worn')
