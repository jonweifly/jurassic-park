"""Budget-neutral finishing pass for the exported dinosaur roster.

Moves disconnected brow ridges and dorsal scutes onto the actual smoothed skin,
and gives the mandible skin its species' atlas tile. Indices, rig and animation buffers are unchanged. Decorative scutes inherit the
weights of the skin below them; all other original weights remain unchanged. The editable Blender originals stay upstream
of this repeatable shipping pass; package_dinosaur_roster calls it after export.
"""
import json
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
VERSION = 4
BODY = dict(small_raptor=1, raptor=2, young_trex=3, trex=4, spitter=5, elite_raptor=6, alpha_trex=7)

def closest_triangle(p, a, b, c):
    ab, ac, ap = b-a, c-a, p-a
    d1, d2 = np.dot(ab, ap), np.dot(ac, ap)
    if d1 <= 0 and d2 <= 0: return a
    bp = p-b
    d3, d4 = np.dot(ab, bp), np.dot(ac, bp)
    if d3 >= 0 and d4 <= d3: return b
    vc = d1*d4-d3*d2
    if vc <= 0 and d1 >= 0 and d3 <= 0: return a+ab*d1/(d1-d3)
    cp = p-c
    d5, d6 = np.dot(ab, cp), np.dot(ac, cp)
    if d6 >= 0 and d5 <= d6: return c
    vb = d5*d2-d1*d6
    if vb <= 0 and d2 >= 0 and d6 <= 0: return a+ac*d2/(d2-d6)
    va = d3*d6-d5*d4
    if va <= 0 and d4-d3 >= 0 and d5-d6 >= 0:
        return b+(c-b)*(d4-d3)/((d4-d3)+(d5-d6))
    return a+ab*(vb/(va+vb+vc))+ac*(vc/(va+vb+vc))

def refine(path):
    kind = path.stem.removesuffix('_v2')
    raw = path.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+size])
    if doc.get('extras', {}).get('dinosaur_surface_refinement') == VERSION:
        return doc['extras']['dinosaur_surface_report']
    previous_version = doc.get('extras', {}).get('dinosaur_surface_refinement', 0)
    binary = bytearray(raw[28+size:])
    widths = dict(SCALAR=1, VEC2=2, VEC3=3, VEC4=4, MAT4=16)
    types = {5126:'<f4', 5125:'<u4', 5123:'<u2', 5121:'<u1'}
    def accessor(index):
        a = doc['accessors'][index]; view = doc['bufferViews'][a['bufferView']]
        dtype = np.dtype(types[a['componentType']]); width = widths[a['type']]
        return np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
            offset=view.get('byteOffset',0)+a.get('byteOffset',0),
            strides=(view.get('byteStride',dtype.itemsize*width),dtype.itemsize))
    primitive = doc['meshes'][0]['primitives'][0]; attrs = primitive['attributes']
    points, uv = accessor(attrs['POSITION']), accessor(attrs['TEXCOORD_0'])
    weights, joints = accessor(attrs['WEIGHTS_0']), accessor(attrs['JOINTS_0'])
    triangles = accessor(primitive['indices']).reshape(-1,3)
    # Weld only equal positions for component identification; exported vertices
    # and their UV/tangent seams themselves remain completely unchanged.
    parents = list(range(len(points)))
    def root(i):
        while parents[i] != i: parents[i] = parents[parents[i]]; i = parents[i]
        return i
    def union(a,b): parents[root(a)] = root(b)
    seen = {}
    for index, point in enumerate(points):
        key = tuple(np.round(point,6))
        if key in seen: union(index,seen[key])
        else: seen[key] = index
    for a,b,c in triangles: union(a,b); union(b,c)
    components = {}
    for index in range(len(points)): components.setdefault(root(index),[]).append(index)
    groups = []
    for indices in components.values():
        ids = np.array(indices); p = points[ids]
        names = {}
        for index in ids:
            for joint, weight in zip(joints[index], weights[index]):
                if weight > .01:
                    name = doc['nodes'][doc['skins'][0]['joints'][joint]]['name']
                    names[name] = names.get(name,0)+float(weight)
        groups.append(dict(ids=ids, center=(p.min(0)+p.max(0))/2, size=p.max(0)-p.min(0), bone=max(names,key=names.get)))
    def is_middle(group): return abs(float(group['center'][0])) < .01
    skull = next(g for g in groups if g['bone']=='head' and is_middle(g) and g['size'][2]>.6 and len(g['ids'])>300)
    skull_ids = set(skull['ids'])
    skull_faces = [points[t].copy() for t in triangles if all(i in skull_ids for i in t)]
    core = [g for g in groups if is_middle(g) and len(g['ids'])>300 and g['size'][2]>1 and g['bone']!='head']
    core_ids = {i for g in core for i in g['ids']}
    skin_faces = [points[t].copy() for t in triangles if all(i in core_ids for i in t)]
    brows, scutes, jaw_vertices = 0,0,0
    maximum_shift = 0.0
    for group in ([] if previous_version >= 1 else groups):
        center, extent, ids = group['center'], group['size'], group['ids']
        authored = center.copy()
        if kind in ('young_trex','trex','alpha_trex'):
            authored = np.array([center[0]/1.36,1.8+(center[1]-1.8)/1.45,center[2]-.15])
        elif kind == 'spitter':
            authored = np.array([center[0]/.86,center[1],.8+(center[2]-.8)/1.23])
        if group['bone']=='head' and 80 <= len(ids) <= 180 and 1.98<authored[1]<2.12 and .90<authored[2]<1.12 and abs(authored[0])>.1:
            nearest = min((closest_triangle(center,*face) for face in skull_faces), key=lambda p:np.linalg.norm(p-center))
            delta = nearest-center; length = float(np.linalg.norm(delta))
            shift = delta*max(0,length-.009)/max(length,.000001)
            points[ids] += shift; brows += 1; maximum_shift=max(maximum_shift,float(np.linalg.norm(shift)))
        elif is_middle(group) and len(ids)<150 and extent[0]<.17 and center[1]>1.2 and (group['bone']=='spine' or group['bone'].startswith('tail')):
            # Intersect the real skin at the scute's x/z, not a guessed tail line.
            heights=[]
            for face in skin_faces:
                a,b,c=face
                matrix=np.array([[b[0]-a[0],c[0]-a[0]],[b[2]-a[2],c[2]-a[2]]])
                if abs(np.linalg.det(matrix))<1e-10: continue
                u,v=np.linalg.solve(matrix,center[[0,2]]-a[[0,2]])
                if u>=-1e-5 and v>=-1e-5 and u+v<=1.00001: heights.append(float(a[1]+u*(b[1]-a[1])+v*(c[1]-a[1])))
            if not heights: raise ValueError(f'{kind}: no underlying skin for dorsal scute')
            shift=max(heights)-.004-float(points[ids,1].min())
            points[ids,1]+=shift; scutes+=1; maximum_shift=max(maximum_shift,abs(shift))
        elif group['bone']=='jaw' and is_middle(group) and extent[2]>.5 and len(ids)<200:
            body=BODY[kind]
            uv[ids,0]+=(body%4-2)/4
            uv[ids,1]+=(2-body//4)/4
            jaw_vertices+=len(ids)
    if previous_version < 1 and (brows!=2 or scutes!=17 or not 120<=jaw_vertices<=150):
        raise ValueError(f'{kind}: anatomical component contract changed: {brows,scutes,jaw_vertices}')
    report = doc['extras']['dinosaur_surface_report'].copy() if previous_version >= 1 else dict(name=kind,brow_components=brows,scute_components=scutes,mandible_skin_vertices=jaw_vertices,maximum_shift_metres=round(maximum_shift,5),added_triangles=0)
    contacts = report.get('foreclaw_contacts', []) if previous_version >= 2 else []
    for group in ([] if previous_version >= 2 else groups):
        if not group['bone'].startswith('hand'): continue
        side = group['bone'][-1]
        arm = next(g for g in groups if g['bone']=='upper_arm'+side)
        arm_ids = set(arm['ids'])
        faces = [t for t in triangles if all(i in arm_ids for i in t)]
        ids = group['ids']
        # Root ring of each curved claw, after the subdivision's endpoint shrink.
        root_ids = ids[points[ids,2] < points[ids,2].min()+.008]
        root_point = points[root_ids].mean(0)
        face, nearest = min(((t,closest_triangle(root_point,*points[t])) for t in faces),key=lambda pair:np.linalg.norm(pair[1]-root_point))
        delta = nearest-root_point
        # Embed the base 6mm beyond the actual palm surface; hand weights stay intact.
        shift = delta*(1+.006/max(np.linalg.norm(delta),.000001))
        points[ids] += shift
        contacts.append(dict(bone=group['bone'],root_vertices=root_ids.tolist(),skin_triangle=face.tolist(),shift_metres=round(float(np.linalg.norm(shift)),5)))
    expected_claws = 4 if kind in ('young_trex','trex','alpha_trex') else 6
    if len(contacts)!=expected_claws: raise ValueError(f'{kind}: foreclaw component contract changed: {len(contacts)}')
    report.update(foreclaw_components=len(contacts),foreclaw_contacts=contacts)
    horn_contacts = report.get('cranial_horn_contacts', []) if previous_version >= 3 else []
    if kind == 'alpha_trex' and previous_version < 3:
        head = next(g for g in groups if g['bone']=='head' and is_middle(g) and g['size'][2]>.6 and len(g['ids'])>300)
        head_ids = set(head['ids'])
        head_faces = [t for t in triangles if all(i in head_ids for i in t)]
        for group in groups:
            if group['bone']!='head' or len(group['ids']) != 134 or group['center'][1] < 2.15: continue
            ids = group['ids']; root_ids = ids[points[ids,1] < points[ids,1].min()+.012]
            root_point = points[root_ids].mean(0)
            face, nearest = min(((t,closest_triangle(root_point,*points[t])) for t in head_faces),key=lambda pair:np.linalg.norm(pair[1]-root_point))
            delta = nearest-root_point
            shift = delta*(1+.006/max(np.linalg.norm(delta),.000001))
            points[ids] += shift
            horn_contacts.append(dict(root_vertices=root_ids.tolist(),skin_triangle=face.tolist(),shift_metres=round(float(np.linalg.norm(shift)),5)))
        if len(horn_contacts) != 2: raise ValueError(f'{kind}: cranial horn component contract changed: {len(horn_contacts)}')
    report.update(foreclaw_components=len(contacts),foreclaw_contacts=contacts,cranial_horn_components=len(horn_contacts),cranial_horn_contacts=horn_contacts)
    scute_contacts = []
    core_faces = [t for t in triangles if all(i in core_ids for i in t)]
    for group in groups:
        center, extent, ids = group['center'], group['size'], group['ids']
        if not (is_middle(group) and len(ids)<150 and extent[0]<.17 and center[1]>1.2 and (group['bone']=='spine' or group['bone'].startswith('tail'))): continue
        root_ids = ids[points[ids,1] < points[ids,1].min()+.008]
        root_point = points[root_ids].mean(0)
        face, nearest = min(((t,closest_triangle(root_point,*points[t])) for t in core_faces),key=lambda pair:np.linalg.norm(pair[1]-root_point))
        a,b,c = points[face]
        u,v = np.linalg.lstsq(np.stack((b-a,c-a),axis=1),nearest-a,rcond=None)[0]
        influences = {}
        for vertex,factor in zip(face,[1-u-v,u,v]):
            for joint,weight in zip(joints[vertex],weights[vertex]):
                influences[int(joint)] = influences.get(int(joint),0)+max(0,float(factor*weight))
        top = sorted(influences.items(),key=lambda pair:pair[1],reverse=True)[:4]
        total = sum(value for _,value in top)
        joints[ids] = 0; weights[ids] = 0
        for slot,(joint,weight) in enumerate(top):
            joints[ids,slot] = joint; weights[ids,slot] = weight/total
        scute_contacts.append(dict(root_vertices=root_ids.tolist(),skin_triangle=face.tolist()))
    if len(scute_contacts)!=17: raise ValueError(f'{kind}: scute attachment contract changed: {len(scute_contacts)}')
    report['scute_contacts'] = scute_contacts
    # Keep import-order-independent reference points for native deformation tests.
    for contact in contacts + horn_contacts + scute_contacts:
        contact['root_positions'] = points[contact['root_vertices']].tolist()
        contact['skin_positions'] = points[contact['skin_triangle']].tolist()
    a=doc['accessors'][attrs['POSITION']];a['min']=points.min(0).tolist();a['max']=points.max(0).tolist()
    doc.setdefault('extras',{}).update(dinosaur_surface_refinement=VERSION,dinosaur_surface_report=report)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    binary.extend(b'\0'*((-len(binary))%4))
    body=struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary
    path.write_bytes(struct.pack('<III',0x46546c67,2,12+len(body))+body)
    return report

def refine_all():
    reports=[refine(ROOT/'godot/assets/models'/f'{kind}_v2.glb') for kind in BODY]
    (ROOT/'art/dinosaur-detail-refinement.json').write_text(json.dumps(reports,indent=2)+'\n')
    print(f'DINOSAUR FINISH: {len(reports)} assets, 14 brows / 119 scutes / 36 foreclaws / 2 horns seated, 0 new triangles')

if __name__=='__main__': refine_all()
