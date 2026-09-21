"""Read Warcraft object modifications; no JASS execution. Missing fields inherit Warcraft defaults."""
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).parent
strings = dict(re.findall(r'^STRING[ \t]+(\d+)\n\{\n(.*?)^\}', (ROOT / 'war3map.wts').read_text(encoding='utf-8-sig'), re.M | re.S))
strings = {key: value.rstrip('\n') for key, value in strings.items()}


def resolve(value):
    if isinstance(value, str) and value.startswith('TRIGSTR_'):
        return strings.get(str(int(value[8:])), value)
    return value


def parse(name, extended):
    data = (ROOT / name).read_bytes()
    pos = 0

    def read(fmt):
        nonlocal pos
        value = struct.unpack_from('<' + fmt, data, pos)[0]
        pos += struct.calcsize('<' + fmt)
        return value

    def text():
        nonlocal pos
        end = data.index(0, pos)
        value = data[pos:end].decode('utf-8', errors='replace')
        pos = end + 1
        return value

    version = read('i')
    objects = []
    for kind in ['original_modifications', 'custom_objects']:
        for _ in range(read('i')):
            original = read('4s').decode('latin1')
            custom = read('4s').decode('latin1').strip('\0')
            obj = {'id': custom or original, 'base_id': original, 'kind': kind, 'fields': {}}
            for _ in range(read('i')):
                field = read('4s').decode('latin1')
                typ = read('i')
                level, pointer = (read('i'), read('i')) if extended else (None, None)
                value = read('i') if typ == 0 else read('f') if typ in (1, 2) else text()
                read('4s')
                key = field if level is None else f'{field}:{level}:{pointer}'
                obj['fields'][key] = resolve(value)
            objects.append(obj)
    assert pos == len(data), (name, pos, len(data))
    return {'format_version': version, 'objects': objects}


result = {name: parse(name, ext) for name, ext in [('war3map.w3u', False), ('war3map.w3q', True), ('war3map.w3t', False), ('war3map.w3a', True)]}
(ROOT / 'objects.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')

units = []
for obj in result['war3map.w3u']['objects']:
    f = obj['fields']
    units.append({'id': obj['id'], 'base_id': obj['base_id'], **{k: f.get(v) for k, v in {
        'name': 'unam', 'gold': 'ugol', 'lumber': 'ulum', 'build_time': 'ubld', 'hit_points': 'uhpm',
        'mana': 'umpm', 'speed': 'umvs', 'is_building': 'ubdg', 'builds': 'ubui', 'trains': 'utra',
        'research': 'ures', 'requires': 'ureq', 'upgrade_to': 'uupt', 'tooltip': 'utub', 'abilities': 'uabi',
    }.items()}})
(ROOT / 'units-buildings.json').write_text(json.dumps(units, ensure_ascii=False, indent=2), encoding='utf-8')
research = []
for obj in result['war3map.w3q']['objects']:
    f = obj['fields']
    research.append({'id': obj['id'], 'base_id': obj['base_id'], **{k: f.get(v) for k, v in {
        'name': 'gnam:1:0', 'gold_base': 'gglb:0:0', 'gold_increment': 'gglm:0:0',
        'lumber_base': 'glmb:0:0', 'lumber_increment': 'glmm:0:0',
        'time_base': 'gtib:0:0', 'time_increment': 'gtim:0:0', 'levels': 'glvl:0:0',
        'requires': 'greq:1:0', 'tooltip': 'gub1:1:0',
    }.items()}})
(ROOT / 'research.json').write_text(json.dumps(research, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Parsed {len(units)} unit definitions; null values inherit base Warcraft data and are not zero.')
