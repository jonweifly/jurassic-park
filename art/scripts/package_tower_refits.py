"""Remove duplicated embedded atlas images; reference the existing shared runtime textures."""
import json
import struct
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def package():
    for kind in ('range', 'rapid', 'heavy'):
        path = ROOT/'godot/assets/models'/f'tower_{kind}.glb'
        raw = path.read_bytes()
        length = struct.unpack_from('<I', raw, 12)[0]
        doc = json.loads(raw[20:20+length])
        binary = raw[28+length:]
        dropped = set()
        for image in doc.get('images', []):
            name = image['name']
            target = ROOT/'godot/assets/materials'/f'{name}.png'
            if not target.is_file():
                raise ValueError(f'Missing shared atlas: {target}')
            if 'bufferView' in image:
                dropped.add(image.pop('bufferView'))
            image.pop('mimeType', None)
            image['uri'] = '../materials/' + name + '.png'
        if not dropped:
            continue
        views, buffer, mapping = [], bytearray(), {}
        for i, view in enumerate(doc['bufferViews']):
            if i in dropped:
                continue
            buffer.extend(b'\0' * ((-len(buffer)) % 4))
            offset = view.get('byteOffset', 0)
            mapping[i] = len(views)
            views.append({**view, 'byteOffset': len(buffer)})
            buffer.extend(binary[offset:offset+view['byteLength']])
        for accessor in doc.get('accessors', []):
            if 'bufferView' in accessor:
                accessor['bufferView'] = mapping[accessor['bufferView']]
        doc['bufferViews'] = views
        doc['buffers'][0]['byteLength'] = len(buffer)
        encoded = json.dumps(doc, separators=(',', ':')).encode()
        encoded += b' ' * ((-len(encoded)) % 4)
        buffer.extend(b'\0' * ((-len(buffer)) % 4))
        body = struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + struct.pack('<II', len(buffer), 0x004E4942) + buffer
        path.write_bytes(struct.pack('<III', 0x46546c67, 2, 12+len(body)) + body)
        print(path.name, len(raw), '->', path.stat().st_size)

if __name__ == '__main__':
    package()
