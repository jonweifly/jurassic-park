"""Original assets for the cinematic rainforest study, isolated from production art.

Blender 4.5: --background --python-exit-code 1 --python this_file.py
Coordinates below are Godot metres (+Y up, +Z forward). No external assets.
"""
import bpy
import bmesh
import math
import random
import json
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'godot/assets/cinematic'
SRC = ROOT / 'art/source/cinematic'
OUT.mkdir(parents=True, exist_ok=True)
SRC.mkdir(parents=True, exist_ok=True)
RNG = random.Random(270901)
REPORT = []


def cv(p):
    return (p[0], -p[2], p[1])


def material(name, color, rough=.75, metal=0, emit=0):
    m = bpy.data.materials.new('CIN_' + name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = rough
    bs.inputs['Metallic'].default_value = metal
    if emit:
        bs.inputs['Emission Color'].default_value = (*color, 1)
        bs.inputs['Emission Strength'].default_value = emit
    return m


STEEL = material('Steel', (.16, .20, .19), .48, .72)
DARK = material('BlackMetal', (.042, .06, .06), .53, .62)
OLIVE = material('OlivePaint', (.21, .235, .16), .66, .25)
CONCRETE = material('Concrete', (.38, .385, .335), .96)
YELLOW = material('SafetyYellow', (.67, .43, .12), .65, .12)
IVORY = material('FadedPaint', (.61, .61, .48), .72, .1)
RUBBER = material('Rubber', (.024, .03, .03), .88)
LAMP = material('Lamp', (1, .73, .36), .3, 0, 2.0)
BARK = material('Bark', (.19, .16, .115), .94)
LEAF = material('Foliage', (.23, .32, .155), .76)
SKIN = material('Skin', (.28, .29, .19), .7)
BELLY = material('Belly', (.37, .35, .24), .79)
TEETH = material('Ivory', (.66, .62, .46), .65)
MOUTH = material('Mouth', (.09, .038, .035), .61)
EYE = material('Eye', (.57, .37, .10), .29)
PUPIL = material('Pupil', (.007, .012, .01), .2)
for mat in [SKIN, BELLY, LEAF, BARK]:
    attr = mat.node_tree.nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'Color'
    mat.node_tree.links.new(attr.outputs['Color'], mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)


def finish(obj, mat, bevel=0, smooth=False):
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new('Machined edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod = obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def box(name, p, size, mat=STEEL, bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=cv(p))
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(ob, mat, bevel)


def sphere(name, p, size, mat=SKIN, segments=28, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=cv(p))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(ob, mat, smooth=True)


def tube(name, points, radii, mat=STEEL, sides=12):
    verts, faces = [], []
    pts = [Vector(cv(p)) for p in points]
    for i, p in enumerate(pts):
        t = (pts[min(i+1, len(pts)-1)] - pts[max(i-1, 0)]).normalized()
        ref = Vector((1, 0, 0)) if abs(t.x) < .8 else Vector((0, 1, 0))
        u = t.cross(ref).normalized()
        v = t.cross(u).normalized()
        for k in range(sides):
            a = 2*pi*k/sides
            verts.append(p + radii[i]*(u*cos(a)+v*sin(a)))
    for i in range(len(pts)-1):
        for k in range(sides):
            a = i*sides+k
            b = i*sides+(k+1)%sides
            faces.append((a, b, b+sides, a+sides))
    faces.extend([tuple(reversed(range(sides))), tuple(range((len(pts)-1)*sides, len(pts)*sides))])
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    finish(ob, mat, smooth=True)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def join(objects, name, remesh=0):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    ob = objects[0]
    ob.name = name
    # Move every origin to world zero, ensuring rig weights and GLB coordinates agree.
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    if remesh:
        mod = ob.modifiers.new('Continuous anatomical surface', 'REMESH')
        mod.mode = 'VOXEL'
        mod.voxel_size = remesh
        mod.use_smooth_shade = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod = ob.modifiers.new('Surface relaxation', 'SMOOTH')
        mod.factor = 1.15
        mod.iterations = 4
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod = ob.modifiers.new('Runtime topology', 'DECIMATE')
        mod.ratio = .6
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def vertex_color(ob, base, skin=False):
    colors = ob.data.color_attributes.new(name='Color', type='BYTE_COLOR', domain='POINT')
    for i, v in enumerate(ob.data.vertices):
        p = ob.matrix_world @ v.co
        x, z, y = p.x, -p.y, p.z
        shade = .9 + .085*sin(z*3.7 + sin(y*2.3)) + .045*cos(x*13 + y*7)
        if skin:
            stripes = max(0, sin(z*5.4 + y*3 + sin(y*7)*.25))**4
            shade -= .22*stripes*min(1, max(0, (y-1.8)*1.2))
        colors.data[i].color = (*[min(1, max(0, c*shade)) for c in base], 1)


def export(name):
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for ob in meshes:
        if not ob.data.uv_layers:
            uv = ob.data.uv_layers.new()
            for poly in ob.data.polygons:
                n = poly.normal
                axis = max(range(3), key=lambda k: abs(n[k]))
                for li in poly.loop_indices:
                    p = ob.data.vertices[ob.data.loops[li].vertex_index].co
                    uv.data[li].uv = (p.y, p.z) if axis == 0 else ((p.x, p.z) if axis == 1 else (p.x, p.y))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')), export_format='GLB', export_yup=True,
                              export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
                              export_skins=True, export_texcoords=True, export_normals=True)
    REPORT.append({'name': name, 'vertices': sum(len(o.data.vertices) for o in meshes), 'meshes': len(meshes)})
    print('CINEMATIC ASSET', REPORT[-1], flush=True)


def gate():
    reset()
    for x in [-3.5, 3.5]:
        box('Concrete footing', (x, .28, 0), (1.0, .56, 1.4), CONCRETE, .07)
        box('Gate tower', (x, 2.4, 0), (.48, 4.2, .7), DARK, .025)
        for y in [.7, 2.7, 4.2]:
            box('Collar', (x, y, 0), (.60, .14, .82), STEEL)
            for dx in [-.20, .20]:
                tube('Anchor bolt', [(x+dx, y, .39), (x+dx, y, .435)], [.036, .036], STEEL, 6)
        box('Hazard backing', (x, 1.0, .365), (.49, 1.15, .03), YELLOW, .004)
        for y in [.55, .83, 1.11, 1.39]:
            ob = box('Hazard stripe', (x, y, .388), (.49, .12, .016), DARK, .001)
            ob.rotation_euler.y = -.24
        box('Beacon base', (x, 4.53, 0), (.43, .10, .51), STEEL)
        sphere('Amber beacon', (x, 4.66, 0), (.10, .17, .10), LAMP, 16, 10)
    box('Overhead lintel', (0, 4.27, 0), (7.5, .36, .58), DARK)
    box('Park sign', (0, 4.28, .34), (3.9, .50, .075), OLIVE)
    for x in [-2.8, 2.8]:
        box('Floodlight housing', (x, 4.05, .45), (.70, .14, .38), DARK)
        box('Floodlight lens', (x, 3.97, .47), (.58, .025, .27), LAMP, .005)
    fixed = list(bpy.context.scene.objects)
    join([o for o in fixed if o.type == 'MESH'], 'GateFrame')
    for side in [-1, 1]:
        parts = []
        cx = side*1.66
        for y in [.32, 1.15, 3.72]:
            parts.append(box('Horizontal frame', (cx, y, .03), (3.26, .14, .19), STEEL))
        for x in [cx-1.56, cx+1.56]:
            parts.append(box('Upright', (x, 2.0, .03), (.13, 3.54, .19), STEEL))
        for i in range(12):
            x = cx - 1.45 + i*.26
            parts.append(tube('Vertical security bar', [(x, .40, .03), (x, 3.65, .03)], [.021, .021], STEEL, 8))
        for y in [1.7, 2.25, 2.8, 3.35]:
            parts.append(tube('Fence strand', [(cx-1.53, y, .06), (cx+1.53, y, .06)], [.010, .010], STEEL, 6))
        parts.append(tube('Diagonal brace', [(cx-1.5, .40, .07), (cx+1.5, 3.6, .07)], [.035, .035], DARK))
        parts.append(box('Reinforced kickplate', (cx, .73, .09), (3.06, .63, .08), OLIVE))
        for x in [cx-1.3, cx+1.3]:
            parts.append(tube('Wheel', [(x, .19, -.05), (x, .19, .13)], [.15, .15], DARK, 20))
        join(parts, 'GateLeft' if side < 0 else 'GateRight')
    export('security_gate')


def generator():
    reset()
    box('Concrete service pad', (0, .1, 0), (4.3, .2, 3.1), CONCRETE, .07)
    for z in [-.84, .84]:
        box('Skid rail', (0, .28, z), (3.1, .20, .17), DARK)
    box('Generator enclosure', (0, 1.03, 0), (2.95, 1.30, 1.65), OLIVE, .09)
    box('Weather cap', (0, 1.72, 0), (3.08, .12, 1.79), STEEL, .035)
    box('Radiator shadow', (-.6, 1.03, .844), (1.44, .85, .025), DARK, .015)
    for j in range(12):
        box('Cooling louvre', (-.6, .66+j*.065, .876), (1.37, .022, .040), STEEL, .004)
    box('Control recess', (.79, 1.15, .85), (.80, .55, .035), DARK)
    box('Instrument glass', (.69, 1.23, .878), (.40, .22, .015), RUBBER, .002)
    for x in [.59, .72, .85]:
        box('Instrument indicator', (x, 1.25, .89), (.045, .12, .012), LAMP, .003)
    for x in [.54, .74, .94]:
        tube('Control dial', [(x, .99, .864), (x, .99, .91)], [.045, .045], DARK, 16)
    box('Lower access panel', (.75, .64, .85), (.88, .25, .05), OLIVE, .009)
    for x in [-1.36, .28, 1.24]:
        for y in [.52, 1.54]:
            tube('Panel bolt', [(x, y, .86), (x, y, .89)], [.025, .025], IVORY, 6)
    tube('Exhaust', [(-1.10, 1.71, -.45), (-1.1, 2.65, -.45), (-1.1, 2.73, -.73)], [.075]*3, DARK)
    tube('Muffler', [(-1.1, 1.9, -.45), (-1.1, 2.4, -.45)], [.125, .125], STEEL, 24)
    box('Electrical cabinet', (1.69, 1.2, -.55), (.42, 1.45, .63), IVORY)
    box('Electrical cabinet door', (1.69, 1.2, -.21), (.35, 1.30, .045), STEEL)
    for x in [-1.5, 1.5]:
        for z in [-1.17, 1.17]:
            tube('Protective bollard', [(x, .18, z), (x, .96, z)], [.075, .075], YELLOW, 16)
            tube('Bollard black band', [(x, .64, z), (x, .79, z)], [.079, .079], DARK, 16)
    for j in range(3):
        points = []
        for i in range(34):
            a = i/33*2*pi
            points.append((.7+cos(a)*(.6+j*.07), .23+j*.023, 1.14+sin(a)*.43))
        tube('Coiled service cable', points, [.018]*len(points), RUBBER, 6)
    join([o for o in bpy.context.scene.objects if o.type == 'MESH'], 'Generator')
    export('diesel_generator')


def cabin():
    reset()
    box('Foundation', (0, .16, 0), (4.5, .32, 3.5), CONCRETE, .06)
    box('Service building', (0, 1.52, 0), (4.1, 2.6, 3.1), OLIVE, .035)
    for x in [-1.96, 1.96]:
        for z in [-1.47, 1.47]:
            box('Corner channel', (x, 1.57, z), (.14, 2.8, .16), STEEL)
    for i in range(26):
        box('Front cladding rib', (-1.94+i*.155, 1.52, 1.56), (.024, 2.52, .045), STEEL, .002)
    box('Front door', (-1.16, 1.36, 1.61), (.86, 2.05, .11), DARK)
    box('Door inset', (-1.16, 1.44, 1.68), (.68, 1.48, .03), OLIVE)
    tube('Door handle', [(-.87, 1.18, 1.72), (-.87, 1.38, 1.72)], [.025, .025], IVORY)
    box('Window frame', (.73, 1.82, 1.65), (1.67, .91, .10), DARK)
    box('Window', (.73, 1.82, 1.712), (1.51, .76, .018), material('CabinGlass', (.17, .22, .19), .2, .3))
    box('Window mullion', (.73, 1.82, 1.738), (.045, .82, .026), STEEL)
    box('Roof', (0, 2.91, 0), (4.65, .16, 3.8), DARK)
    for i in range(28):
        box('Roof standing seam', (-2.23+i*.166, 3.0, 0), (.022, .055, 3.72), STEEL, .003)
    box('Front overhang', (0, 2.78, 1.95), (4.54, .13, 1.3), DARK)
    for x in [-2.06, 2.06]:
        tube('Porch post', [(x, .15, 2.32), (x, 2.77, 2.32)], [.046, .046], STEEL)
    box('Doorstep', (-1.1, .19, 1.95), (1.4, .32, .66), CONCRETE)
    box('Porch light', (-1.1, 2.57, 1.79), (.78, .06, .12), LAMP)
    tube('Antenna mast', [(-1.7, 3.0, -.9), (-1.7, 5.2, -.9)], [.032, .018], STEEL)
    for y in [4.38, 4.77, 5.03]:
        tube('Antenna element', [(-2.10, y, -.9), (-1.3, y, -.9)], [.012, .012], STEEL, 8)
    join([o for o in bpy.context.scene.objects if o.type == 'MESH'], 'FieldStation')
    export('service_cabin')


def foliage():
    reset()
    trunk_parts = []
    trunk_parts.append(tube('Rainforest trunk', [(0, 0, 0), (.14, 1.4, 0), (-.2, 3.7, .12), (.11, 6.2, .06), (.30, 8.4, .2)], [.57, .38, .29, .17, .02], BARK, 18))
    for j in range(7):
        a = j*2*pi/7
        trunk_parts.append(tube('Buttress root', [(0, 1.4, 0), (cos(a)*.5, .37, sin(a)*.5), (cos(a)*1.45, .02, sin(a)*1.45)], [.23, .15, .015], BARK, 10))
    verts, faces, cols, uvs = [], [], [], []

    def leaf(p, angle, length, width, tilt, color):
        offset = len(verts)
        for k in range(7):
            f = k/6
            span = sin(f*pi)**.85 * width
            for side in [-1, 0, 1]:
                x = p[0]+cos(angle)*length*f - sin(angle)*span*side
                z = p[2]+sin(angle)*length*f + cos(angle)*span*side
                y = p[1]+sin(f*pi)*length*.10 + tilt*f - abs(side)*span*.14
                verts.append(cv((x, y, z)))
                uvs.append((f, (side+1)*.5))
                cols.append((*[c*(.8+.2*sin(f*pi)) for c in color], 1))
        for k in range(6):
            for s in range(2):
                a = offset+k*3+s
                faces.append((a, a+3, a+4, a+1))

    for j in range(14):
        a = j*2.4
        h = 5.7 + (j%4)*.73
        radius = 2.3 + RNG.random()*.8
        tip = (cos(a)*radius, h, sin(a)*radius)
        trunk_parts.append(tube('Canopy branch', [(0, h-1.35, 0), (tip[0]*.55, h-.25, tip[2]*.55), tip], [.13, .067, .012], BARK, 10))
        for k in range(6):
            ba = a+k*1.05
            start = (tip[0]*.78, h-.09, tip[2]*.78)
            end = (tip[0]+cos(ba)*1.18, h+RNG.uniform(-.2, .52), tip[2]+sin(ba)*1.18)
            trunk_parts.append(tube('Leaf twig', [start, end], [.016, .002], BARK, 6))
            for m in range(9):
                f = m/9
                p = tuple(start[v]+(end[v]-start[v])*f for v in range(3))
                for side in [-1, 1]:
                    shade = RNG.uniform(.72, 1.28)
                    leaf(p, ba+side*.97, RNG.uniform(.31, .57), RNG.uniform(.06, .115), RNG.uniform(-.15, .08), [.15*shade, .235*shade, .09*shade])
    ob = join(trunk_parts, 'Trunk')
    vertex_color(ob, (.19, .16, .115))
    me = bpy.data.meshes.new('Botanical foliage')
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new('Foliage', me)
    bpy.context.collection.objects.link(ob)
    finish(ob, LEAF, smooth=True)
    layer = me.color_attributes.new(name='Color', type='BYTE_COLOR', domain='POINT')
    for i, col in enumerate(cols):
        layer.data[i].color = col
    uv = me.uv_layers.new()
    for loop in me.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    export('rainforest_canopy')


def fern():
    reset()
    stems, verts, faces, cols, uvs = [], [], [], [], []
    for j in range(10):
        angle = j*2.399
        radius = RNG.uniform(.58, .98)
        height = RNG.uniform(.42, .78)
        points = []
        for k in range(14):
            f = k/13
            points.append((cos(angle)*radius*f, .04+height*sin(f*pi*.76), sin(angle)*radius*f))
        stems.append(tube('Fern rachis', points, [.008*(1-k/15) for k in range(14)], BARK, 5))
        for k in range(1, 13):
            f = k/13
            origin = Vector(points[k])
            length = (.04+.17*sin(pi*f)**.7)*(radius/.8)
            for side in [-1,1]:
                a = angle+side*1.03
                direction = Vector((cos(a), .18, sin(a)))
                lateral = Vector((-sin(a), 0, cos(a)))
                offset = len(verts)
                for t, w, rise in [(0,0,0),(.42,-.027,-.009),(.42,0,.015),(.42,.027,-.009),(1,0,-.015)]:
                    p = origin+direction*(t*length)+lateral*w+Vector((0,rise,0))
                    verts.append(cv(p))
                    uvs.append((t, .5+w*16))
                    shade=RNG.uniform(.83,1.17)
                    cols.append((.10*shade,.18*shade,.055*shade,1))
                for tri in [(0,1,2),(0,2,3),(1,4,2),(2,4,3)]: faces.append(tuple(offset+v for v in tri))
    ob=join(stems,'FernStems')
    vertex_color(ob,(.15,.19,.065))
    me=bpy.data.meshes.new('Pinnate fern leaves')
    me.from_pydata(verts,[],faces)
    me.update()
    ob=bpy.data.objects.new('Foliage',me)
    bpy.context.collection.objects.link(ob)
    finish(ob,LEAF,smooth=True)
    colors=me.color_attributes.new(name='Color',type='BYTE_COLOR',domain='POINT')
    for i,col in enumerate(cols): colors.data[i].color=col
    uv=me.uv_layers.new()
    for loop in me.loops: uv.data[loop.index].uv=uvs[loop.vertex_index]
    export('rainforest_fern')


def dinosaur():
    reset()
    body = []
    body.append(sphere('Torso', (0, 2.17, -.32), (.70, .82, 1.28)))
    body.append(sphere('Chest', (0, 2.29, .54), (.59, .66, .84)))
    body.append(tube('Curved neck', [(0, 2.30, .51), (0, 2.68, .93), (0, 3.08, 1.16), (0, 3.25, 1.51)], [.48, .41, .37, .38], SKIN, 28))
    for side in [-1, 1]:
        body.append(sphere('Haunch', (side*.64, 1.79, -.45), (.43, .74, .67)))
        body.append(tube('Leg muscle', [(side*.65, 1.65, -.38), (side*.74, 1.02, .18), (side*.75, .60, -.14), (side*.72, .26, -.22)], [.34, .24, .135, .10], SKIN, 20))
        body.append(tube('Ankle', [(side*.72, .45, -.20), (side*.72, .17, -.13), (side*.72, .14, .18)], [.105, .10, .13], SKIN, 18))
    tail_points, tail_radii = [], []
    for j in range(19):
        f = j/18
        tail_points.append((sin(f*pi)*.27, 2.02-f*.65+f*f*.30, -1.13-f*4.50))
        tail_radii.append(.46*(1-f)**1.25+.009)
    body.append(tube('Muscular tail', tail_points, tail_radii, SKIN, 24))
    body_ob = join(body, 'RexSkin', .041)
    vertex_color(body_ob, (.255, .275, .177), True)
    headparts = [sphere('Cranium', (0, 3.28, 1.63), (.51, .44, .58)),
                 box('Deep rectangular muzzle', (0, 3.26, 2.24), (.77, .51, 1.29), SKIN, .13),
                 sphere('Nasal bridge', (0, 3.39, 2.05), (.30, .19, .62))]
    for side in [-1, 1]:
        headparts.append(sphere('Cheek', (side*.37, 3.14, 1.68), (.22, .30, .32)))
        headparts.append(tube('Orbital ridge', [(side*.43, 3.64, 1.46), (side*.52, 3.62, 1.70), (side*.47, 3.51, 1.96)], [.09, .08, .035], SKIN, 16))
    head = join(headparts, 'RexSkull', .027)
    vertex_color(head, (.26, .275, .18), True)
    jaw = join([sphere('Mandible', (0, 2.90, 2.05), (.40, .13, .72), SKIN),
                sphere('Lower hinge', (0, 2.97, 1.62), (.46, .25, .30), SKIN)], 'RexJaw', .022)
    vertex_color(jaw, (.32, .32, .22), True)
    bone_meshes = [('body', body_ob), ('head', head), ('jaw', jaw)]
    mouth = sphere('Mouth interior', (0, 3.024, 2.16), (.361, .026, .59), MOUTH)
    bone_meshes.append(('jaw', mouth))
    for side in [-1, 1]:
        eye = sphere('Eye socket', (side*.473, 3.47, 1.79), (.068, .060, .079), PUPIL, 20, 12)
        bone_meshes.append(('head', eye))
        eye = sphere('Amber eye', (side*.524, 3.48, 1.82), (.027, .035, .041), EYE, 24, 14)
        bone_meshes.append(('head', eye))
        eye = sphere('Eye pupil', (side*.548, 3.48, 1.825), (.007, .021, .015), PUPIL, 16, 10)
        bone_meshes.append(('head', eye))
        nostril = sphere('Nostril', (side*.342, 3.35, 2.62), (.013, .037, .058), PUPIL, 16, 10)
        bone_meshes.append(('head', nostril))
        for j in range(13):
            z = 1.67+j*.078
            x = side*(.388-.11*max(0, (z-2.1)/.6))
            length = .09+.03*sin(j*pi/13)
            tooth = tube('Upper tooth', [(x, 3.066, z), (x*.98, 3.066-length*.7, z+.021), (x*.97, 3.066-length, z+.01)], [.023, .012, .001], TEETH, 10)
            bone_meshes.append(('head', tooth))
        for j in range(10):
            z = 1.79+j*.085
            x = side*(.335-.09*max(0, (z-2.1)/.6))
            tooth = tube('Lower tooth', [(x, 2.986, z), (x, 3.055, z+.01)], [.017, .001], TEETH, 10)
            bone_meshes.append(('jaw', tooth))
        arm = tube('Forelimb', [(side*.47, 2.40, .86), (side*.62, 2.11, 1.13), (side*.56, 2.05, 1.33)], [.12, .075, .046], SKIN, 16)
        vertex_color(arm, (.26, .275, .18), True)
        bone_meshes.append(('spine', arm))
        for j in range(2):
            claw = tube('Hand claw', [(side*(.55+j*.07), 2.08, 1.31), (side*(.56+j*.07), 1.94, 1.49), (side*(.56+j*.07), 1.89, 1.45)], [.022, .018, .001], DARK, 10)
            bone_meshes.append(('spine', claw))
        for j in range(3):
            x = side*.72+(j-1)*.14
            toe = tube('Load bearing toe', [(side*.72, .17, -.02), (x, .11, .39), (x+(j-1)*.05, .07, .64)], [.080, .065, .030], SKIN, 14)
            vertex_color(toe, (.255, .265, .17), True)
            bone_meshes.append(('root', toe))
            claw = tube('Foot claw', [(x+(j-1)*.05, .08, .60), (x+(j-1)*.06, .10, .72), (x+(j-1)*.06, .035, .84)], [.051, .033, .001], DARK, 12)
            bone_meshes.append(('root', claw))
    # Subtle raised pebbles along the spine; no fantasy spikes.
    for j in range(34):
        f = j/33
        z = .50-f*5.6
        y = 2.96-.38*f if z > -1.1 else 2.25-(abs(z)-1.1)*.105
        scale = .041*(1-f)+.014
        ob = sphere('Dorsal scute', (sin(f*pi)*.13, y, z), (scale, scale*.55, scale*1.4), SKIN, 10, 6)
        vertex_color(ob, (.21, .235, .145), True)
        bone_meshes.append(('spine' if z > -1.1 else ('tail1' if z > -3.1 else 'tail2'), ob))

    bones = [('root', (0, 1.7, -.4), (0, 2.0, -.4), None),
             ('spine', (0, 2.0, -.4), (0, 2.5, .65), 'root'),
             ('neck', (0, 2.5, .65), (0, 3.15, 1.38), 'spine'),
             ('head', (0, 3.15, 1.38), (0, 3.24, 2.55), 'neck'),
             ('jaw', (0, 3.04, 1.50), (0, 2.9, 2.45), 'head'),
             ('tail1', (0, 2.03, -1.0), (.2, 1.75, -3.15), 'root'),
             ('tail2', (.2, 1.75, -3.15), (0, 1.68, -5.55), 'tail1')]
    data = bpy.data.armatures.new('CinematicRexSkeleton')
    rig = bpy.data.objects.new('RexRig', data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, a, b, parent in bones:
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = cv(a), cv(b)
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for tag, ob in bone_meshes:
        # Apply locations before rigging; analytical weights use global game coordinates.
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        groups = {name: ob.vertex_groups.new(name=name) for name, *_ in bones}
        for v in ob.data.vertices:
            z, y = -v.co.y, v.co.z
            if tag == 'body':
                if z < -3.0:
                    w = max(0, min(1, (-z-2.7)/1.1))
                    weights = {'tail1': 1-w, 'tail2': w}
                elif z < -1.05:
                    w = max(0, min(1, (-z-1.05)/.8))
                    weights = {'root': 1-w, 'tail1': w}
                elif y < 1.55:
                    weights = {'root': 1}
                elif z > .6:
                    w = max(0, min(1, (z-.6)/.7))
                    weights = {'spine': 1-w, 'neck': w}
                else:
                    w = max(0, min(.8, (y-1.55)*.7))
                    weights = {'root': 1-w, 'spine': w}
            else:
                weights = {tag: 1}
            for bone_name, w in weights.items():
                if w > 0:
                    groups[bone_name].add([v.index], w, 'REPLACE')
        ob.parent = rig
        mod = ob.modifiers.new('Cinematic breathing rig', 'ARMATURE')
        mod.object = rig
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 241
    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'
    for frame in range(1, 242, 8):
        t = (frame-1)/240*2*pi
        for name in ['spine', 'neck', 'head', 'jaw', 'tail1', 'tail2']:
            bone = rig.pose.bones[name]
            bone.rotation_euler = (0, 0, 0)
            if name == 'spine': bone.rotation_euler.x = .011*sin(t*2)
            if name == 'neck': bone.rotation_euler.z = .042*sin(t)
            if name == 'head': bone.rotation_euler.x = .018*sin(t+1)
            if name == 'jaw': bone.rotation_euler.x = -.025-.022*sin(t*2)
            if name == 'tail1': bone.rotation_euler.z = .035*sin(t+.6)
            if name == 'tail2': bone.rotation_euler.z = .054*sin(t+1.1)
            bone.keyframe_insert('rotation_euler', frame=frame)
    rig.animation_data.action.name = 'observe'
    scene.frame_set(1)
    export('cinematic_rex')


if __name__ == '__main__':
    import sys
    requested = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    jobs = {'gate': gate, 'generator': generator, 'cabin': cabin, 'foliage': foliage, 'fern': fern, 'dinosaur': dinosaur}
    for name, job in jobs.items():
        if not requested or name in requested:
            job()
    manifest = OUT/'asset_manifest.json'
    existing = json.loads(manifest.read_text()) if manifest.exists() and requested else []
    updates = {item['name']: item for item in existing+REPORT}
    manifest.write_text(json.dumps(list(updates.values()), indent=2)+'\n')
