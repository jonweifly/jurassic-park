"""Build three original tower silhouettes, shared expedition atlas, editable Blender sources.
Run .tools/Blender.app/Contents/MacOS/Blender -b --python art/scripts/build_tower_refits.py
Coordinates in metres, Y-up. Two render meshes per tower, no new gameplay collision.
"""
import ast, bpy, bmesh, json, math
from math import sin, cos, pi
from mathutils import Vector
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'godot/assets/models'
SRC = ROOT/'art/source'
ICONS = ROOT/'godot/assets/ui/towers'
ICONS.mkdir(parents=True, exist_ok=True)
# Reuse geometry/UV helpers without executing the original asset generator.
source = ast.parse((ROOT/'art/scripts/build_assets.py').read_text())
for node in source.body:
    if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in ['cv', 'material', 'Mesh', 'empty']:
        exec(compile(ast.Module(body=[node], type_ignores=[]), 'build_assets.py', 'exec'))
atlas = bpy.data.images.load(str(ROOT/'art/textures/expedition_albedo.png'))
rmap = bpy.data.images.load(str(ROOT/'art/textures/expedition_roughness.png'))
normalmap = bpy.data.images.load(str(ROOT/'art/textures/expedition_normal.png'))
rmap.colorspace_settings.name = normalmap.colorspace_settings.name = 'Non-Color'
MAT = material('Expedition_PBR')
LEAF = MAT

def frame(m, height, width, color):
    m.box((0,.09,0),(1.78,.18,1.78),3)
    for x in [-1,1]:
        for z in [-1,1]:
            m.tube([(x*.68,.16,z*.68),(x*width,height,z*width)],[.11,.085],4,8)
            for y in [.3,height-.2]:
                f = (y-.16)/(height-.16); k = .68+(width-.68)*f
                m.box((x*k,y,z*k),(.235,.09,.235),6,.01)
        for y in [.6,height-.35]:
            m.tube([(x*.61,y,-.59),(x*.61,y,.59)],[.065]*2,4)
        m.tube([(x*.64,.4,-.61),(x*width,height-.18,width)],[.055]*2,13)
        m.tube([(-.61,.4,x*.64),(width,height-.18,x*width)],[.055]*2,13)
    for i in range(9): m.box(((i-4)*.18,height,0),(.173,.12,1.6),4)
    for x in [-.77,.77]:
        for z in [-.7,.7]: m.tube([(x,height,z),(x,height+.42,z)],[.028]*2,6)
        m.tube([(x,height+.42,-.7),(x,height+.42,.7)],[.035]*2,4)
    m.tube([(-.77,height+.42,-.7),(.77,height+.42,-.7)],[.035]*2,4)
    for x in [-.21,.21]: m.tube([(x,.12,.8),(x,height,.73)],[.025]*2,4)
    for i in range(int(height/.19)):
        y=.15+i*.19; m.tube([(-.21,y,.8),(.21,y,.8)],[.023]*2,4)
    # Riveted role plate is secondary to silhouette, not the only identifier.
    m.box((0,height-.35,.73),(.54,.47,.04),color)
    for x in [-.21,.21]:
        for y in [height-.52,height-.18]: m.ellipsoid((x,y,.76),(.025,.025,.017),6,n=6,r=3)

def bow(m, x, span, length, thick, tile=4):
    m.box((x,.08,.10),(.15*thick,.16*thick,length),tile)
    pts=[(x-span/2,.13,.06),(x-span*.34,.17,.26),(x,.18,.4),(x+span*.34,.17,.26),(x+span/2,.13,.06)]
    m.tube(pts,[.035*thick,.05*thick,.065*thick,.05*thick,.035*thick],13,8)
    m.tube([pts[0],(x,.17,-length*.35),pts[-1]],[.01]*3,7,6)
    m.tube([(x,.22,-length*.39),(x,.22,length*.57)],[.014*thick]*2,6,8)
    m.loft([((x,.22,length*.55),.04*thick,.035*thick),((x,.22,length*.67),.001,.001)],6,4,axis='z')
    for z in [-.23,.10]: m.box((x,.04,z),(.20*thick,.06,.08),6)
    m.tube([(x,.0,-.35),(x,.23,-.35)],[.036]*2,6)

def crate(m,x,y,z):
    m.box((x,y+.21,z),(.40,.42,.38),13)
    for dx in [-.14,.14]: m.box((x+dx,y+.21,z+.2),(.03,.43,.02),6)
    for dx in [-.12,-.04,.04,.12]:
        m.tube([(x+dx,y+.30,z),(x+dx,y+.85,z)],[.012]*2,6,6)
        m.box((x+dx,y+.8,z),(.045,.10,.015),7)

report=[]
for kind in ['range','rapid','heavy']:
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    m=Mesh('TowerStructure'); gunmesh=Mesh('Weapon')
    height={'range':2.8,'rapid':1.55,'heavy':1.8}[kind]
    color={'range':12,'rapid':10,'heavy':13}[kind]
    frame(m,height,.54 if kind=='range' else .66,color)
    m.loft([((0,height+.06,0),.31,.31),((0,height+.22,0),.22,.22)],6,16)
    gun=empty('Gun',(0,height+.25,0)); recoil=empty('Recoil'); recoil.parent=gun
    if kind=='range':
        bow(gunmesh,0,1.35,1.65,1.0)
        # Long optical sight, counterweight and narrow observation mast.
        gunmesh.tube([(0,.40,-.32),(0,.40,.28)],[.055,.04],6,12)
        for z in [-.23,.2]: gunmesh.tube([(0,.1,z),(0,.4,z)],[.024]*2,6)
        gunmesh.box((0,.05,-.79),(.26,.24,.23),3)
        m.tube([(-.66,height,-.53),(-.66,height+1.0,-.53)],[.027]*2,6)
        # Folded pennant with real depth and tapered end.
        m.loft([((-.45,height+.55,-.53),.18,.025),((-.45,height+.88,-.53),.24,.025)],12,4)
        crate(m,.39,.17,-.35)
        muzzle=empty('Muzzle',(0,.22,1.10)); muzzle.parent=recoil
    elif kind=='rapid':
        for x in [-.42,.42]:
            bow(gunmesh,x,.82,1.06,.82)
            # Vertical bolt magazines make the twin weapons legible at RTS scale.
            gunmesh.box((x,.43,-.15),(.27,.50,.28),10)
            for dx in [-.08,0,.08]: gunmesh.box((x+dx,.47,.002),(.035,.34,.025),6)
        gunmesh.box((0,-.01,0),(1.22,.14,.45),6)
        for x in [-.52,.52]: crate(m,x,.16,-.42)
        for i in range(3): m.box(((i-1)*.13,height-.34,.758),(.065,.24,.014),7)
        for side,x in [('Muzzle',-.42),('MuzzleRight',.42)]:
            muzzle=empty(side,(x,.22,.72)); muzzle.parent=recoil
    else:
        # Four battered armored buttresses and a broad, low siege bow.
        for x in [-1,1]:
            for z in [-1,1]:
                m.loft([((x*.63,.20,z*.63),.27,.27),((x*.61,.58,z*.61),.21,.21),((x*.55,1.2,z*.55),.12,.12)],3,4)
        for x in [-.78,.78]:
            m.box((x,height+.15,0),(.13,.65,1.32),6)
            m.box((x*1.08,height+.16,0),(.025,.46,.8),13)
        bow(gunmesh,0,2.55,1.65,1.65,3)
        for x in [-.23,.23]: gunmesh.tube([(x,-.06,-.65),(x,-.06,.51)],[.045]*2,6)
        gunmesh.box((0,.02,-.68),(.63,.34,.35),3)
        gunmesh.tube([(-.43,.1,-.65),(.43,.1,-.65)],[.08]*2,6,12)
        for x in [-.46,.46]: gunmesh.tube([(x,-.06,-.65),(x,.26,-.65)],[.025]*2,6)
        m.box((0,height-.37,.77),(.60,.44,.11),13)
        for x in [-.2,0,.2]: m.box((x,height-.37,.835),(.045,.28,.025),6)
        muzzle=empty('Muzzle',(0,.22,1.1)); muzzle.parent=recoil
    body=m.object(); weapon=gunmesh.object(); weapon.parent=recoil
    # Flat structural faces with beveled edges; avoids swollen timber shading.
    for ob in [body,weapon]:
        for face in ob.data.polygons: face.use_smooth=False
    bpy.context.preferences.filepaths.save_version=0
    for im in [atlas,rmap,normalmap]: im.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/f'tower_{kind}.blend'),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'tower_{kind}.glb'),export_format='GLB',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    triangles=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in [body,weapon])
    report.append(dict(name=kind,triangles=triangles,meshes=2,height=height,weapon='Gun/Recoil/Muzzle',footprint='existing 2m cell'))
    # Consistent real-model thumbnails, transparent backdrop, same framing/scale.
    scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=24
    scene.render.resolution_x=384; scene.render.resolution_y=384; scene.render.resolution_percentage=100
    scene.render.film_transparent=True; scene.world.color=(.22,.22,.22)
    bpy.ops.object.camera_add(location=(5,-7,5)); camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,1.8))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO'; camera.data.ortho_scale=4.5; scene.camera=camera
    for loc,power,size in [((2,-4,7),850,5),((-4,-1,4),600,4),((1,3,5),1000,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc); light=bpy.context.object
        light.data.energy=power; light.data.shape='DISK'; light.data.size=size
        light.rotation_euler=(Vector((0,0,1.5))-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(ICONS/f'{kind}.png')
    bpy.ops.render.render(write_still=True)
(ROOT/'art/tower-refits-manifest.json').write_text(json.dumps(report,indent=2)+'\n')

# Keep runtime atlas data shared; editable sources retain packed textures.
import runpy
runpy.run_path(str(ROOT/"art/scripts/package_tower_refits.py"), run_name="__main__")
