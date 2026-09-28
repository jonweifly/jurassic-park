"""Adapt approved cinematic art to the existing game's dimensions and contracts.

Blender --background --python-exit-code 1 --python this_file.py
Retains the production tyrannosaur skeleton/animations and the gate's Leaf pivot.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/source/cinematic'
OUT = ROOT / 'godot/assets/cinematic/gameplay'
DEST = SOURCE / 'gameplay'
OUT.mkdir(parents=True, exist_ok=True)
DEST.mkdir(parents=True, exist_ok=True)
REPORT = []


def open_source(name):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / (name + '.blend')))
    bpy.context.scene.frame_set(0)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def apply_dimensions(scale):
    for ob in meshes():
        ob.location = Vector(tuple(ob.location[i] * scale[i] for i in range(3)))
        for v in ob.data.vertices:
            v.co = Vector(tuple(v.co[i] * scale[i] for i in range(3)))


def export(name, animations=False):
    # Tangents require triangulated geometry; clean degenerate decimation faces.
    for ob in meshes():
        bpy.context.view_layer.objects.active = ob
        ob.data.validate(clean_customdata=False)
        mod = ob.modifiers.new('Export triangulation', 'TRIANGULATE')
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(DEST / (name + '.blend')), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB',
        export_yup=True, export_animations=animations, export_animation_mode='NLA_TRACKS',
        export_force_sampling=True, export_frame_range=False, export_skins=True,
        export_tangents=True, export_cameras=False, export_lights=False)
    REPORT.append({'name': name, 'meshes': len(meshes()),
        'triangles': sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes())})
    print('GAMEPLAY ASSET', REPORT[-1], flush=True)


def decimate(ob, ratio):
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new('Gameplay geometry budget', 'DECIMATE')
    mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)


def static_assets():
    open_source('diesel_generator')
    apply_dimensions((.47, .55, .64))
    export('generator')
    open_source('service_cabin')
    apply_dimensions((.405, .44, .60))
    export('lab')
    open_source('security_gate')
    apply_dimensions((.235, .48, .46))
    leaves = [o for o in meshes() if o.name.startswith(('GateLeft', 'GateRight'))]
    bpy.ops.object.select_all(action='DESELECT')
    for ob in leaves: ob.select_set(True)
    bpy.context.view_layer.objects.active = leaves[0]
    bpy.ops.object.join()
    leaf = leaves[0]
    leaf.name = 'Leaf'
    bpy.context.scene.cursor.location = (-.78, 0, 0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    export('gate')
    # A fence occupies one existing 2m navigation cell, with a separate silhouette.
    steel = bpy.data.materials.get('CIN_Steel')
    dark = bpy.data.materials.get('CIN_BlackMetal')
    concrete = bpy.data.materials.get('CIN_Concrete')
    amber = bpy.data.materials.get('CIN_SafetyYellow')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    def box(at, size, mat):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(at[0],-at[2],at[1]))
        ob=bpy.context.object
        ob.dimensions=(size[0],size[2],size[1])
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        ob.data.materials.append(mat)
        bevel=ob.modifiers.new('Rounded steel edges','BEVEL')
        bevel.width=.012
        bevel.segments=2
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    for x in [-.82,.82]:
        box((x,.08,0),(.34,.16,.42),concrete)
        box((x,.98,0),(.13,1.86,.18),steel)
        box((x,.58,.105),(.14,.5,.028),amber)
        for y in [.4,.56,.72]: box((x,y,.122),(.145,.05,.018),dark)
    for y in [.34,.59,.84,1.09,1.34,1.59,1.84]:
        box((0,y,.05),(1.7,.018,.018),steel)
        for x in [-.82,.82]: box((x,y,.067),(.17,.065,.07),concrete)
    box((0,1.27,.086),(.32,.24,.025),amber)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active=meshes()[0]
    bpy.ops.object.join()
    bpy.context.object.name='Barrier'
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    export('shelter')


def vegetation():
    open_source('rainforest_canopy')
    apply_dimensions((.48, .48, .50))
    for ob in meshes(): decimate(ob, .35 if ob.name == 'Foliage' else .55)
    export('rainforest_tree')
    for ob in meshes(): decimate(ob, .27 if ob.name == 'Foliage' else .45)
    export('rainforest_tree_lod')
    open_source('rainforest_fern')
    for ob in meshes(): decimate(ob, .70)
    export('fern')


def clamp(v):
    return max(0., min(1., v))


def rex():
    open_source('cinematic_rex')
    objects = meshes()
    for ob in objects:
        matrix = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = matrix
        ob.modifiers.clear()
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for ob in list(bpy.context.scene.objects):
        if ob.type == 'ARMATURE': bpy.data.objects.remove(ob, do_unlink=True)
    apply_dimensions((.61, .61, .61))
    with bpy.data.libraries.load(str(ROOT / 'art/source/trex_v2.blend'), link=False) as (source, target):
        target.objects = ['Rig']
    rig = target.objects[0]
    assert rig is not None, 'Production tyrannosaur rig missing'
    bpy.context.collection.objects.link(rig)
    rig.name = 'Rig'
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
    for ob in objects:
        tag = ob.name
        old_names = {g.index:g.name for g in ob.vertex_groups}
        original = [{old_names[g.group]:g.weight for g in v.groups} for v in ob.data.vertices]
        ob.vertex_groups.clear()
        groups = {b.name:ob.vertex_groups.new(name=b.name) for b in rig.data.bones}
        for v, prior in zip(ob.data.vertices, original):
            x, y, z = v.co.x, v.co.z, -v.co.y
            side = 'L' if x < 0 else 'R'
            if tag.startswith(('Load bearing toe', 'Foot claw')):
                weights = {'foot'+side:1.}
            elif tag.startswith('RexSkin') and z < -.65:
                if z < -1.9:
                    t = clamp((-z-1.7)/.7)
                    weights = {'tail1':1-t,'tail2':t}
                elif z < -1.12:
                    t = clamp((-z-.95)/.5)
                    weights = {'tail0':1-t,'tail1':t}
                else:
                    t = clamp((-z-.65)/.4)
                    weights = {'root':1-t,'tail0':t}
            elif tag.startswith('RexSkin') and abs(x) > .24 and y < 1.35 and -.63 < z < .48:
                if y > 1.04:
                    t = clamp((1.35-y)/.31)
                    weights = {'root':1-t,'thigh'+side:t}
                elif y > .40:
                    t = clamp((.76-y)/.27)
                    weights = {'thigh'+side:1-t,'shin'+side:t}
                else:
                    t = clamp((.42-y)/.18)
                    weights = {'shin'+side:1-t,'foot'+side:t}
            elif tag.startswith('Dorsal scute') and z < -.65:
                weights = {'tail0' if z > -1.35 else ('tail1' if z > -2.1 else 'tail2'):1.}
            else:
                weights = {k:w for k,w in prior.items() if k in groups}
                if not weights: weights = {'root':1.}
            total = sum(weights.values())
            for name, value in weights.items():
                if value > 0: groups[name].add([v.index], value/total, 'REPLACE')
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active = next(o for o in objects if o.name == 'RexSkin')
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = 'CinematicTyrannosaurSurface'
    body.parent = rig
    mod = body.modifiers.new('Production animation rig', 'ARMATURE')
    mod.object = rig
    bpy.context.scene.frame_set(0)
    export('trex', animations=True)


if __name__ == '__main__':
    import sys
    requested=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['buildings', 'vegetation']
    for name,job in [('buildings',static_assets),('vegetation',vegetation),('rex',rex)]:
        if not requested or name in requested: job()
    manifest=OUT/'manifest.json'
    prior=json.loads(manifest.read_text()) if requested and manifest.exists() else []
    manifest.write_text(json.dumps(list({x['name']:x for x in prior+REPORT}.values()),indent=2)+'\n')
