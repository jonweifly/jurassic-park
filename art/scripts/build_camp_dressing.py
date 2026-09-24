"""Original small camp assets, built in Blender; game coordinates +Y up.
Rebuild: Blender --background --python art/scripts/build_camp_dressing.py
Decorations fit existing building footprints and never supply collision geometry.
"""
import bpy, math, json
from mathutils import Vector
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'godot/assets/models'; SOURCE=ROOT/'art/source'
def cv(v): return (v[0],-v[2],v[1])
def mat(name,color,rough=.8,metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=rough
    bs.inputs['Metallic'].default_value=metal
    return m
wood=mat('Weathered timber',(.20,.135,.067))
edge=mat('Timber edges',(.31,.23,.12))
steel=mat('Dark iron',(.12,.16,.155),.52,.55)
canvas=mat('Olive canvas',(.15,.205,.12))
cream=mat('Faded identification paint',(.56,.49,.31))
rubber=mat('Rubber and cable',(.025,.037,.031),.9)
glass=mat('Amber lamp',(.69,.35,.08),.38)
bs=glass.node_tree.nodes.get('Principled BSDF'); bs.inputs['Emission Color'].default_value=(.6,.22,.025,1); bs.inputs['Emission Strength'].default_value=.35

def finish(obj,material,bevel=0):
    obj.data.materials.append(material)
    if bevel:
        mod=obj.modifiers.new('Real edge bevel','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=obj.modifiers.new('Weighted edge normals','WEIGHTED_NORMAL'); mod.keep_sharp=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj
def box(name,p,size,material=wood,bevel=.008):
    bpy.ops.mesh.primitive_cube_add(size=1,location=cv(p)); obj=bpy.context.object; obj.name=name
    obj.dimensions=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(obj,material,bevel)
def tube(name,a,b,r,material=steel,vertices=12):
    a,b=Vector(cv(a)),Vector(cv(b)); delta=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=delta.length,location=(a+b)/2)
    obj=bpy.context.object; obj.name=name; obj.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    return finish(obj,material,.004)
def crate(x,y,z,s=.45):
    box('Crate dark gaps',(x,y+s*.5,z),(s,s,s),rubber)
    for i in range(5):
        offset=(i-2)*s/5
        for side in [-1,1]: box('Individual board',(x+offset,y+s*.5,z+side*s*.5),(s*.185,s,.025),wood)
        box('Lid board',(x+offset,y+s,z),(s*.185,.024,s),wood)
    for a in [-.34,.34]:
        for side in [-1,1]: box('Metal strap',(x+a*s,y+s*.5,z+side*(s*.5+.018)),(.028,s+.035,.013),steel,.003)
    box('Supply label',(x,y+s*.57,z+s*.5+.018),(s*.35,s*.22,.008),cream,.002)
def drum(x,z):
    tube('Fuel drum body',(x,.10,z),(x,.65,z),.20,canvas,20)
    for h in [.12,.26,.49,.63]: tube('Rolled steel band',(x,h-.012,z),(x,h+.012,z),.211,steel,20)
    tube('Filler cap',(x+.09,.65,z),(x+.09,.675,z),.035,steel)
def lamp(x,y,z):
    tube('Lamp glass',(x,y,z),(x,y+.17,z),.062,glass)
    for h in [y-.025,y+.17]: tube('Lamp housing',(x,h,z),(x,h+.026,z),.086,steel)
    for a in range(4):
        dx=math.cos(a*math.pi/2)*.064; dz=math.sin(a*math.pi/2)*.064
        tube('Lamp guard',(x+dx,y,z+dz),(x+dx,y+.18,z+dz),.005,steel,6)
    tube('Lamp hook',(x,y+.18,z),(x,y+.29,z),.012,steel)

report=[]
for kind in ['tent','tower','generator','lab']:
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    if kind=='tent':
        crate(-.68,.075,.93,.36)
        tube('Rolled bed canvas',(.36,.19,.95),(.80,.19,.95),.105,canvas,16)
        for x in [.43,.72]: tube('Bedroll strap',(x-.012,.19,.95),(x+.012,.19,.95),.111,steel)
        lamp(.88,.60,.72)
        box('Welcome mat',(0,.055,1.0),(.55,.025,.4),canvas,.01)
    elif kind=='tower':
        for x in [-.72,.72]:
            for z in [-.62,.62]: tube('Deck railing post',(x,1.82,z),(x,2.28,z),.024,steel)
            tube('Deck side rail',(x,2.25,-.62),(x,2.25,.62),.027,wood)
        tube('Rear safety rail',(-.72,2.25,-.62),(.72,2.25,-.62),.027,wood)
        crate(.54,.18,.45,.35)
        for i in range(5): tube('Spare bolts',(.40+i*.05,.56,.45),(.40+i*.05,1.05,.49),.009,steel,6)
    elif kind=='generator':
        drum(.82,-.52)
        box('Battery',(0,.28,.73),(.55,.26,.24),rubber)
        for x in [-.18,.18]: box('Battery terminal',(x,.44,.73),(.05,.04,.05),steel,.003)
        for i in range(12):
            a=i*math.pi*2/12; b=(i+1)*math.pi*2/12
            tube('Ground cable',(.62+math.cos(a)*.28,.06,.57+math.sin(a)*.26),(.62+math.cos(b)*.28,.06,.57+math.sin(b)*.26),.017,rubber,6)
    else:
        for x in [-.56,.56]:
            box('Window header',(x,1.48,.91),(.46,.035,.15),steel)
            for y in [1.07,1.14,1.21]: box('Window lower slats',(x,y,.92),(.34,.026,.025),canvas,.003)
        tube('Roof gutter',(-.98,1.76,-.91),(.98,1.76,-.91),.035,steel)
        tube('Drainpipe',(-.94,1.76,-.91),(-.94,.20,-.91),.028,steel)
        box('Door step',(0,.11,1.0),(.68,.12,.29),wood)
        box('Station name plate',(0,1.54,.90),(.49,.14,.014),steel)
        for x in [-.13,0,.13]: box('Station ID',(x,1.54,.912),(.055,.085,.005),cream,.001)
        lamp(.39,.85,.93)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active=bpy.context.selected_objects[0]
    bpy.ops.object.join(); ob=bpy.context.object; ob.name='CampDressing'
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/f'{kind}_dressing.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{kind}_dressing.glb'),export_format='GLB',export_yup=True,export_animations=False)
    report.append({'name':kind+'_dressing','vertices':len(ob.data.vertices),'polygons':len(ob.data.polygons),'collision':False})
(ROOT/'art/camp-dressing-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
