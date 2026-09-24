"""Build original skinned dinosaur assets with shared scale PBR and anatomical silhouettes.
Uses the project's mesh/rig/IK exporter, not external images or third-party geometry.
Run: .tools/Blender.app/Contents/MacOS/Blender --background --python art/scripts/build_dinosaur_roster.py
"""
import bpy, bmesh, math, json, sys, types, shutil
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'art/scripts/build_assets.py').read_text()
# Reuse the original meshing/IK library without overwriting the shared environment atlas.
source=source.replace("'expedition_albedo'", "'dinosaur_albedo'").replace("'expedition_roughness'", "'dinosaur_roughness'").replace("'expedition_normal'", "'dinosaur_normal'")
base=types.ModuleType('dinosaur_mesh_library');base.__file__=str(ROOT/'art/scripts/build_assets.py')
exec(compile(source,base.__file__,'exec'),base.__dict__)
N=base.N; tile=N//4
palette=['b9b291','657b56','49664c','906449','a38256','346f69','526779','53463f','5d7850','303f38','e0d2ac','17211c','d0a151','806143','a9b4a0','b45336']
rng=np.random.default_rng(650206)
albedo=np.ones((N,N,4),np.float32); rough=np.ones_like(albedo); normals=np.ones_like(albedo)
for i,color in enumerate(palette):
 y,x=np.mgrid[0:tile,0:tile].astype(float)
 # Staggered pebble scales, dark seams, soft domed normal relief and mottled pigmentation.
 sx=(x/12+(np.floor(y/10)%2)*.5)%1-.5; sy=(y/10)%1-.5
 r=np.sqrt((sx*1.85)**2+(sy*1.85)**2)
 ridge=np.clip(1-r,0,1)**.65
 pattern=.87+.14*np.sin(x*.045+np.sin(y*.03)*1.4)*np.cos(y*.027)
 stripes=1-.22*(np.sin(x*.07+np.sin(y*.02)*1.8)>.58)
 rgb=np.array([int(color[j:j+2],16)/255 for j in (0,2,4)])
 value=pattern*stripes*(.77+.26*ridge)+(rng.random((tile,tile))-.5)*.035
 a,b=(i//4)*tile,(i%4)*tile
 albedo[a:a+tile,b:b+tile,:3]=np.clip(rgb*value[:,:,None],0,1)
 rough[a:a+tile,b:b+tile,:3]=(.76+.12*(1-ridge))[:,:,None]
 dy,dx=np.gradient(ridge); normals[a:a+tile,b:b+tile,:3]=np.stack([.5-dx*.6,.5-dy*.6,np.ones_like(x)],axis=-1)
for im,arr in [(base.atlas,albedo),(base.rmap,rough),(base.normalmap,normals)]:
 im.pixels.foreach_set(arr.ravel());im.save()
base.MAT.name='Dinosaur_Scale_PBR'
base.MAT.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.82
# Add details before skin binding, so every ridge, membrane and plate deforms with anatomy.
def detail(m,bones,name,rex):
 kind=base.roster_kind
 body={'small_raptor':1,'raptor':2,'young_trex':3,'trex':4,'spitter':5,'elite_raptor':6,'alpha_trex':7}[kind]
 for i,t in enumerate(m.tiles):
  if t in (8,13):m.tiles[i]=body
  elif t==7:m.tiles[i]=10
  elif t==10:m.tiles[i]=12
  elif t in (4,9):m.tiles[i]=9
 # Continuous scaled breast and abdomen patches, not painted flat rectangles.
 for j in range(7):
  z=-.4+j*.115
  m.ellipsoid((0,.86+j*.025,z),(.19,.035,.09),0,{'root':max(0,1-j/6),'spine':min(1,j/6)},n=14,r=4)
 for side in (-1,1):
  # Nasal folds, lower lip, throat tendons and clavicle curves.
  x=side*(.29 if rex else .18)
  m.tube([(x,1.86,1.0),(x*.88,1.80,1.26),(x*.7,1.79,1.53)],[.022,.024,.013],body,8,{'head':1})
  m.tube([(side*.13,1.72,.7),(side*.18,1.45,.52),(side*.27,1.28,.3)],[.035,.05,.025],body,8,{'neck':.5,'spine':.5})
  m.ellipsoid((side*.20,1.77,1.10),(.09,.016,.22),15,{'jaw':1},n=14,r=4)
  # Sculpted small orbital bosses and rows of flat scales along flanks.
  for j in range(10):
   z=-.56+j*.094
   x=side*(.34 if rex else .28)
   m.ellipsoid((x,1.42+.04*math.sin(j*.7),z),(.038,.025,.048),body,{'spine':.65,'root':.35},n=8,r=4)
 # Segmented dorsal scutes run into the counterbalance tail.
 for j in range(17):
  z=.4-j*.17; y=1.70 if z>-.5 else 1.30+max(0,-z-1.3)*.13
  bone='spine' if z>-.5 else ('tail0' if z> -1.35 else ('tail1' if z>-2.1 else 'tail2'))
  height=(.17 if rex else .07)*(1-j/23)
  if kind=='alpha_trex':height*=2.2
  m.loft([((0,y,z),.065 if rex else .035,.07),((0,y+height,z-.03),.006,.025)],body,8,[{bone:1}]*2)
 if kind=='spitter':
  # Two cranial crests and articulated bilateral throat fan with actual membranes.
  for side in (-1,1):
   m.loft([((side*.105,2.04,.87),.025,.13),((side*.12,2.30,1.12),.013,.20),((side*.10,2.10,1.48),.006,.04)],12,12,[{'head':1}]*3)
   anchor=(side*.12,1.67,.72)
   for j in range(8):
    a=-1.2+j*.31
    end=(side*(.24+.5*math.cos(a)),1.67+.5*math.sin(a),.54)
    m.tube([anchor,end],[.027,.008],12,7,{'neck':.5,'head':.5})
    if j:
     v0=m.vert(anchor,(0,.5),{'neck':.5,'head':.5});v1=m.vert(previous,(1,(j-1)/7),{'neck':.5,'head':.5});v2=m.vert(end,(1,j/7),{'neck':.5,'head':.5});m.face((v0,v1,v2),15)
    previous=end
 elif kind=='elite_raptor':
  for j in range(12):
   z=.64-j*.14; y=1.85 if z>0 else 1.64
   bone='neck' if z>.4 else 'spine'
   for side in (-1,1):
    m.tube([(side*.08,y,z),(side*.16,y+.29,z-.19),(side*.18,y+.38,z-.29)],[.034,.022,.001],14,7,{bone:1})
  for side in (-1,1):
   # Enlarged curled sickle claw stays attached to the foot skeleton.
   m.tube([(side*.31,.14,.22),(side*.29,.36,.38),(side*.28,.25,.56)],[.055,.042,.001],11,10,{'foot'+('L' if side<0 else 'R'):1})
 elif kind=='alpha_trex':
  for side in (-1,1):
   for j in range(5):
    m.ellipsoid((side*.43,1.50,-.36+j*.16),(.13,.075,.115),13,{'root':.4,'spine':.6},n=10,r=5)
   m.tube([(side*.28,2.15,.92),(side*.32,2.41,.76),(side*.30,2.49,.68)],[.09,.06,.002],10,12,{'head':1})
   # Old scars are narrow sculpted raised skin, bound to the cranium.
   for j in range(3):
    m.tube([(side*.33,2.12,1.06+j*.075),(side*.32,1.95,1.10+j*.075)],[.009,.006],0,5,{'head':1})
 # Narrow young animals, stretched spitter muzzle, massive boss chest; feet retain IK contacts.
 for i,p in enumerate(m.v):
  w=m.weights[i];x,z,y=p; forward=-z
  if kind=='spitter' and ('head' in w or 'jaw' in w):forward=.8+(forward-.8)*1.23;x*=.86
  if kind=='elite_raptor' and ('root' in w or 'spine' in w):x*=1.10
  if kind=='alpha_trex' and ('spine' in w or 'neck' in w):x*=1.20
  m.v[i]=(x,-forward,y)

base.detail=detail
# Build fresh anatomical surface meshes from lofts, then bind using existing tested IK.
start=source.index('def dinosaur(name):');end=source.index('\ndef tree(name):',start)
fn=source[start:end].replace("c,18,", "c,24,").replace("c,16,", "c,24,")
fn=fn.replace("r=rig(bones,[m.object()]); animate(r,name); export(name)", "detail(m,bones,name,rex); r=rig(bones,[m.object()]); animate(r,name); export(roster_kind+'_v2')")
exec(fn,base.__dict__)
# Bake distinct attack acting into each species while retaining the same clip contract.
animate_start=source.index('def animate(r,kind):'); animate_end=source.index('\ndef export(name):',animate_start)
acting=source[animate_start:animate_end]
acting=acting.replace("   if name=='death':", """   if name=='attack':
    strike=sin(min(1,phase/.75)*pi)
    if roster_kind=='spitter':
     rot('neck',-.24*strike); rot('head',.38*strike); rot('jaw',-.85*strike)
    elif roster_kind=='elite_raptor':
     rot('spine',.36*strike); rot('upper_armL',-.8*strike); rot('upper_armR',-.8*strike)
    elif roster_kind=='alpha_trex':
     rot('spine',-.20*strike); rot('neck',.55*strike); rot('jaw',-.70*strike)
     rot('thighR',.28*strike); rot('shinR',-.3*strike)
   if name=='death':""")
exec(acting,base.__dict__)
original_export=base.export
def export_triangulated(name):
 for ob in bpy.context.scene.objects:
  if ob.type!='MESH':continue
  bm=bmesh.new();bm.from_mesh(ob.data)
  bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
 original_export(name)
base.export=export_triangulated
base.MAN=[]
for kind in ['small_raptor','raptor','young_trex','trex','spitter','elite_raptor','alpha_trex']:
 base.roster_kind=kind
 base.dinosaur('trex' if kind in ['young_trex','trex','alpha_trex'] else 'raptor')
(ROOT/'art/dinosaur-roster-manifest.json').write_text(json.dumps(base.MAN,indent=2)+'\n')
# Dedicated native wrappers use shared pawn behavior and independent production meshes.
for item in base.MAN:
 kind=item['name'].removesuffix('_v2')
 wrapper=(ROOT/'godot/scenes/models/raptor.tscn').read_text()
 wrapper=wrapper.replace('res://assets/models/raptor.glb',f'res://assets/models/{kind}_v2.glb').replace('name="raptor"',f'name="{kind}"')
 # raptor wrapper may already have been rewritten by an earlier iteration.
 import re
 wrapper=re.sub(r'res://assets/models/[^" ]+\.glb',f'res://assets/models/{kind}_v2.glb',wrapper)
 (ROOT/f'godot/scenes/models/{kind}.tscn').write_text(wrapper)

for key in ['albedo','roughness','normal']:
 shutil.copy2(ROOT/f'art/textures/dinosaur_{key}.png',ROOT/f'godot/assets/materials/dinosaur_{key}.png')

# Rebuilds must retain shared textures and Godot's production animation import hook.
import runpy
runpy.run_path(str(ROOT/'art/scripts/package_dinosaur_roster.py'),run_name='__main__')
for item in base.MAN:
 path=ROOT/'godot/assets/models'/(item['name']+'.glb.import')
 if path.exists():
  text=path.read_text().replace('import_script/path=""','import_script/path="res://tools/asset_post_import.gd"')
  path.write_text(text)
