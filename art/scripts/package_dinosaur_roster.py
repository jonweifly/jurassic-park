"""Share dinosaur textures without rewriting other assets or animation/skin accessors."""
import json
import struct
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
NAMES = ('dinosaur_albedo', 'dinosaur_roughness', 'dinosaur_normal')

def package():
    for path in sorted((ROOT / 'godot/assets/models').glob('*_v2.glb')):
        if path.stem not in {x['name'] for x in json.loads((ROOT/'art/dinosaur-roster-manifest.json').read_text())}:
            continue
        raw = path.read_bytes()
        length = struct.unpack_from('<I', raw, 12)[0]
        doc = json.loads(raw[20:20+length])
        binary = raw[28+length:]
        dropped = set()
        for image in doc.get('images', []):
            if image.get('name') not in NAMES:
                continue
            if 'bufferView' in image:
                dropped.add(image.pop('bufferView'))
            image.pop('mimeType', None)
            image['uri'] = '../materials/' + image['name'] + '.png'
        if not dropped:
            continue
        views, buf, mapping = [], bytearray(), {}
        for i, view in enumerate(doc['bufferViews']):
            if i in dropped:
                continue
            buf.extend(b'\0' * ((-len(buf)) % 4))
            offset = view.get('byteOffset', 0)
            mapping[i] = len(views)
            views.append({**view, 'byteOffset': len(buf)})
            buf.extend(binary[offset:offset+view['byteLength']])
        for accessor in doc.get('accessors', []):
            if 'bufferView' in accessor:
                accessor['bufferView'] = mapping[accessor['bufferView']]
        doc['bufferViews'] = views
        doc['buffers'][0]['byteLength'] = len(buf)
        encoded = json.dumps(doc, separators=(',', ':')).encode()
        encoded += b' ' * ((-len(encoded)) % 4)
        buf.extend(b'\0' * ((-len(buf)) % 4))
        body = struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + struct.pack('<II', len(buf), 0x004E4942) + buf
        path.write_bytes(struct.pack('<III', 0x46546c67, 2, 12+len(body)) + body)
        print(path.name, len(raw), '->', path.stat().st_size)
    # Native mesh / animation contracts stay intact during budget-neutral finishing.
    import runpy
    runpy.run_path(str(ROOT/'art/scripts/refine_dinosaur_geometry.py'),run_name='__main__')
    for filename in ['dinosaur-roster-manifest.json', 'asset-manifest.json']:
        path = ROOT/'art'/filename
        records = json.loads(path.read_text())
        for record in records:
            if record['name'].endswith('_v2'):
                record['runtime_bytes'] = (ROOT/'godot/assets/models'/(record['name']+'.glb')).stat().st_size
        path.write_text(json.dumps(records, indent=2)+'\n')

if __name__ == '__main__':
    package()
