"""Deterministic shared dinosaur PBR surfaces, usable without starting Blender.
The .blend sources and seven production GLBs use these same external maps.
Run: .tools/art-venv/bin/python art/scripts/build_dinosaur_surface.py
"""
from pathlib import Path
import numpy as np

def dinosaur_surface(size=1024):
    N=size
    tile=N//4
    palette=['b9b291','657b56','49664c','906449','a38256','346f69','526779','53463f','5d7850','303f38','e0d2ac','17211c','d0a151','806143','a9b4a0','b45336']
    rng=np.random.default_rng(650206)
    albedo=np.ones((N,N,4),np.float32); rough=np.ones_like(albedo); normals=np.ones_like(albedo)
    for i,color in enumerate(palette):
     y,x=np.mgrid[0:tile,0:tile].astype(float)
     # Offset organic scales have narrow recessed seams, softer centres and finer
     # satellite scales.  Keep the shared 1K atlas budget rather than enlarging it.
     row=np.floor(y/10); col=np.floor(x/12+(row%2)*.5)
     cell=np.sin(col*2.39+row*5.17+i)*.5+.5
     sx=(x/12+(row%2)*.5)%1-.5; sy=(y/10)%1-.5
     r=np.sqrt((sx*(1.80+.14*cell))**2+(sy*(1.83+.11*cell))**2)
     ridge=np.clip(1-r,0,1)**.55
     fine=np.sin(x*1.63+np.sin(y*.8)) * np.sin(y*1.47)
     height=ridge+.045*fine*ridge
     pattern=.92+.095*np.sin(x*.045+np.sin(y*.03)*1.4)*np.cos(y*.027)
     stripes=1-.17*np.clip((np.sin(x*.065+np.sin(y*.023)*1.8)-.28)/.64,0,1)
     rgb=np.array([int(color[j:j+2],16)/255 for j in (0,2,4)])
     value=pattern*stripes*(.81+.24*ridge)*(.97+.06*cell)+(rng.random((tile,tile))-.5)*.025
     roughness=.72+.17*(1-ridge)+.035*cell
     if i==10: # enamel: no reptile scales on the teeth
      value=.91+.055*np.sin(x*.075)+.02*np.sin(y*.83+x*.04)
      height=.028*np.sin(y*.83+x*.04); roughness=np.full_like(x,.39)
     elif i==11: # dark keratin / pupil / nostril recesses
      value=.90+.05*np.sin(y*.18); height=.045*np.sin(y*.32); roughness=np.full_like(x,.43)
     elif i==12: # amber eyes and display crests catch a restrained highlight
      roughness=.34+.14*(1-ridge)
     elif i==15: # oral tissue reads as soft and moist, not scaled armor
      value=.81+.08*np.sin(y*.047)*np.cos(x*.06)
      height=.06*np.sin(x*.19+y*.08); roughness=np.full_like(x,.48)
     a,b=(i//4)*tile,(i%4)*tile
     albedo[a:a+tile,b:b+tile,:3]=np.clip(rgb*value[:,:,None],0,1)
     rough[a:a+tile,b:b+tile,:3]=roughness[:,:,None]
     dy,dx=np.gradient(height); n=np.stack([-dx*1.75,-dy*1.75,np.ones_like(x)],axis=-1)
     n/=np.linalg.norm(n,axis=-1,keepdims=True)
     normals[a:a+tile,b:b+tile,:3]=n*.5+.5
    return albedo,rough,normals

def write_surface():
    from PIL import Image
    root=Path(__file__).resolve().parents[2]
    maps=dinosaur_surface()
    for name,pixels in zip(('albedo','roughness','normal'),maps):
        rgb=pixels[:,:,:3]
        # Blender's image pixels use a bottom-left origin.  The existing source
        # PNGs store these authored values directly; match that contract exactly.
        encoded=np.round(np.clip(rgb[::-1],0,1)*255).astype(np.uint8)
        for directory in ('art/textures','godot/assets/materials'):
            path=root/directory/f'dinosaur_{name}.png'
            Image.fromarray(encoded,'RGB').save(path,optimize=True)
        print(f'DINOSAUR SURFACE {name}: {encoded.shape[1]}x{encoded.shape[0]}')

if __name__=='__main__':
    write_surface()
