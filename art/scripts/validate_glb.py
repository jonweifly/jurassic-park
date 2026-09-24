"""Structural glTF validation independent of Godot: finite data, skin, animation and budgets."""
import json,struct,math,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--assets',default='godot/assets/models')
parser.add_argument('--report',default='art/validation.json')
args=parser.parse_args()
errors=[]; reports=[]
for file in sorted((ROOT/args.assets).glob('*.glb')):
 data=file.read_bytes(); magic,version,length=struct.unpack_from('<III',data)
 assert magic==0x46546c67 and version==2 and length==len(data),file
 jl=struct.unpack_from('<I',data,12)[0]; doc=json.loads(data[20:20+jl]); offset=20+jl
 binary=data[offset+8:]; counts={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
 formats={5126:'f',5125:'I',5123:'H',5122:'h',5121:'B',5120:'b'}
 def values(idx):
  a=doc['accessors'][idx]; v=doc['bufferViews'][a['bufferView']]; fmt=formats[a['componentType']]; width=counts[a['type']]; size=struct.calcsize(fmt)*width; start=v.get('byteOffset',0)+a.get('byteOffset',0); stride=v.get('byteStride',size)
  return [struct.unpack_from('<'+fmt*width,binary,start+i*stride) for i in range(a['count'])]
 for idx,a in enumerate(doc.get('accessors',[])):
  for row in values(idx):
   if not all(math.isfinite(v) for v in row): errors.append(f'{file.name}: nonfinite accessor {idx}');break
 tris=0; weighted=0; blends=0
 for mesh in doc.get('meshes',[]):
  for primitive in mesh['primitives']:
   attrs=primitive['attributes']; tris+=doc['accessors'][primitive['indices']]['count']//3
   if 'WEIGHTS_0' in attrs:
    weighted+=doc['accessors'][attrs['WEIGHTS_0']]['count']
    for row in values(attrs['WEIGHTS_0']):
     if abs(sum(row)-1)>.002: errors.append(f'{file.name}: unnormalized skin weights');break
     blends+=sum(v>.01 for v in row)>1
 clips=[a.get('name') for a in doc.get('animations',[])]
 if file.stem in ['survivor','raptor','trex'] or file.stem in {r['name'] for r in json.loads((ROOT/'art/dinosaur-roster-manifest.json').read_text())}:
  if weighted==0 or blends==0:errors.append(f'{file.name}: missing actual weighted deformation')
  for clip in ['idle','walk','attack','death']+(['chop','mine','build','carry','carry_idle'] if file.stem=='survivor' else []):
   if clip not in clips:errors.append(f'{file.name}: missing {clip}')
 reports.append(dict(name=file.stem,triangles=tris,weighted_vertices=weighted,blended_vertices=blends,bones=sum(len(s['joints']) for s in doc.get('skins',[])),clips=clips,bytes=len(data)))
result=dict(assets=len(reports),errors=errors,results=reports)
(ROOT/args.report).write_text(json.dumps(result,indent=2)+'\n')
print(f'GLB VALIDATION: {len(reports)} assets, {len(errors)} errors')
for e in errors:print(e)
raise SystemExit(bool(errors))
