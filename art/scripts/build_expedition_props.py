"""Original static landmark props for Godot. Run with Blender --background --python.
Only writes the named expedition props, never overwrites the core character assets.
"""
import bpy, math, random
from mathutils import Vector
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'godot/assets/expedition'
SOURCE = ROOT / 'art/source/expedition'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)

def material(name, color, metallic=0, rough=.68):
    m = bpy.data.materials.new(name); m.diffuse_color=(*color,1)
    m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1); p.inputs['Metallic'].default_value=metallic; p.inputs['Roughness'].default_value=rough
    return m
metal=material('Weathered painted steel',(.19,.24,.22),.65,.55)
silver=material('Brushed antenna alloy',(.55,.60,.54),.72,.42)
canvas=material('Faded field canvas',(.43,.39,.22))
wood=material('Dark expedition timber',(.23,.13,.065))
white=material('Ivory equipment shell',(.76,.76,.62),.1)
green=material('Medical green',(.13,.39,.24))
black=material('Rubber and seals',(.037,.047,.043),0,.82)
cream=material('Shell',(.67,.61,.37),0,.86)
orange=material('Safety ochre',(.7,.37,.075),0,.65)

def finish(obj, mat, bevel=0):
    obj.data.materials.append(mat)
    if bevel:
        mod=obj.modifiers.new('Worn manufactured edges','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons: p.use_smooth=True
    return obj

def box(name,p,size,mat,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p); ob=bpy.context.object; ob.name=name; ob.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(ob,mat,bevel)

def rod(name,a,b,r,mat,segments=10):
    a,b=Vector(a),Vector(b); delta=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=r,depth=delta.length,location=(a+b)/2)
    ob=bpy.context.object; ob.name=name; ob.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    return finish(ob,mat)

def sphere(name,p,scale,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=p)
    ob=bpy.context.object; ob.name=name; ob.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(ob,mat)

def start():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def export(name):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.context.view_layer.objects.active = next(ob for ob in bpy.context.selected_objects if ob.type == 'MESH')
    bpy.ops.object.join()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)

def mast(height=3.0):
    box('Concrete foot',(0,0,.07),(.85,.72,.14),metal)
    corners=[(-.30,-.22),(.30,-.22),(0,.30)]
    for x,y in corners:
        rod('Mast leg',(x,y,.1),(x*.38,y*.38,height),.035,metal)
        sphere('Anchor bolt',(x,y,.16),(.065,.065,.035),silver)
    for k in range(5):
        z0=.2+k*(height-.3)/5; z1=z0+(height-.3)/5
        t0=1-.6*z0/height; t1=1-.6*z1/height
        for i,(x,y) in enumerate(corners):
            nx,ny=corners[(i+1)%3]
            rod('Cross bracing',(x*t0,y*t0,z0),(nx*t1,ny*t1,z1),.016,silver,8)
    box('Weatherproof control box',(.32,-.08,.62),(.29,.23,.4),green)
    for z in [.52,.58,.64,.70]: box('Vent slot',(.474,-.08,z),(.016,.15,.015),black,.002)
    rod('Cable',(0,.16,.15),(0,.1,height-.2),.018,black)

start(); mast(3.1)
# Continuous paraboloid mesh with real wall thickness and a separate feed assembly.
verts=[(0,0,0)]; faces=[]; segments=32; rings=8
for k in range(1,rings+1):
    r=.65*k/rings
    for j in range(segments):
        a=j*math.tau/segments; verts.append((r*math.cos(a),r*math.sin(a),.27*(r/.65)**2))
for j in range(segments): faces.append((0,1+j,1+(j+1)%segments))
for k in range(rings-1):
    for j in range(segments):
        a=1+k*segments+j; b=1+k*segments+(j+1)%segments
        faces.append((a,b,b+segments,a+segments))
mesh=bpy.data.meshes.new('Parabolic dish surface'); mesh.from_pydata(verts,[],faces); mesh.update()
dish=bpy.data.objects.new('Formed parabolic dish',mesh); bpy.context.collection.objects.link(dish)
finish(dish,silver); dish.location=(0,0,3.0); dish.rotation_euler.x=math.radians(72)
mod=dish.modifiers.new('Dish wall','SOLIDIFY'); mod.thickness=.025
bpy.context.view_layer.objects.active=dish; bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.context.view_layer.update()
def dp(p): return dish.matrix_world @ Vector(p)
for j in range(3):
    a=j*math.tau/3; rod('Feed support',dp((.55*math.cos(a),.55*math.sin(a),.2)),dp((0,0,.56)),.015,metal)
sphere('Receiver horn',dp((0,0,.54)),(.075,.075,.1),orange)
rod('Hinged dish support',(0,0,2.7),(0,0,3.0),.09,metal)
export('relay_antenna')

start()
box('Medical case',(0,0,.29),(.84,.48,.5),white,.055)
box('Rubber seam',(0,0,.46),(.86,.50,.035),black,.015)
box('Case lid',(0,0,.52),(.84,.48,.1),white,.035)
for x in [-.30,.30]:
    box('Front latch',(x,-.25,.42),(.075,.04,.15),metal,.008)
    box('Hinge',(x,.25,.49),(.14,.04,.04),silver,.009)
rod('Handle left',(-.14,0,.56),(-.14,0,.67),.023,black)
rod('Handle right',(.14,0,.56),(.14,0,.67),.023,black)
rod('Handle grip',(-.14,0,.67),(.14,0,.67),.028,black)
box('Medical mark vertical',(0,-.247,.29),(.09,.018,.25),green,.004)
box('Medical mark horizontal',(0,-.248,.29),(.25,.018,.09),green,.004)
export('medical_case')

start(); mast(2.65)
rod('Sensor spindle',(0,0,2.6),(0,0,3.0),.035,silver)
for j in range(3):
    a=j*math.tau/3; end=(.35*math.cos(a),.35*math.sin(a),2.85)
    rod('Anemometer arm',(0,0,2.85),end,.015,metal,8)
    sphere('Anemometer cup',end,(.095,.095,.07),orange)
rod('Weather vane axis',(-.36,0,3.08),(.38,0,3.08),.018,metal)
box('Vane tail',(-.30,0,3.12),(.20,.035,.20),green,.008)
for j in range(5):
    box('Louvered sensor',(0,.16,1.65+j*.055),(.23,.21,.03),white,.012)
export('weather_mast')

start()
box('Recovered data cabinet',(0,0,.53),(.70,.55,1.06),green,.035)
box('Cabinet face',(0,-.284,.53),(.63,.035,.96),metal,.018)
box('Glass status window',(0,-.308,.76),(.39,.018,.22),black,.008)
for j in range(3): sphere('Status lamp',(-.13+j*.13,-.326,.77),(.025,.012,.025),orange)
rod('Handle',( .23,-.32,.30),(.23,-.32,.56),.022,silver)
for x in [-.29,.29]:
    for z in [.14,.9]: sphere('Panel fixing',(x,-.314,z),(.02,.013,.02),silver)
for j in range(4): box('Cooling slot',(0,-.308,.19+j*.05),(.32,.014,.016),black,.002)
export('archive_cabinet')

start(); random.seed(17)
for j in range(32):
    a=j*math.tau/32; r=random.uniform(.5,.64); b=a+.35
    rod('Nest branch',(r*math.cos(a),r*math.sin(a),.08+random.random()*.13),(r*math.cos(b),r*math.sin(b),.10+random.random()*.10),random.uniform(.023,.039),wood,8)
for x,y in [(-.23,-.1),(.20,.12),(-.02,.24)]:
    egg=sphere('Egg',(x,y,.28),(.18,.15,.25),cream); egg.rotation_euler.y=random.uniform(-.3,.3)
export('sample_eggs')
