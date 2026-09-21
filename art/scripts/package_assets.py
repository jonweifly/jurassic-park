"""Share PBR textures across native GLBs. Repack buffer views with 4-byte alignment.
Keeps skins, mesh indices and animation samplers intact; images use relative asset URIs.
"""
import json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
for path in sorted((ROOT/'godot/assets/models').glob('*.glb')):
 raw=path.read_bytes(); jl=struct.unpack_from('<I',raw,12)[0]; doc=json.loads(raw[20:20+jl]); binary=raw[28+jl:]
 images=doc.get('images',[]); dropped=set()
 for im in images:
  name=im.get('name','')
  if name not in ['expedition_albedo','expedition_roughness','expedition_normal']: continue
  if 'bufferView' in im: dropped.add(im.pop('bufferView'))
  im.pop('mimeType',None); im['uri']='../materials/'+name+'.png'
 if not dropped: continue
 views=[]; buf=bytearray(); mapping={}
 for i,v in enumerate(doc['bufferViews']):
  if i in dropped: continue
  while len(buf)%4:buf.append(0)
  offset=v.get('byteOffset',0); chunk=binary[offset:offset+v['byteLength']]
  mapping[i]=len(views); views.append({**v,'byteOffset':len(buf)});buf.extend(chunk)
 for a in doc.get('accessors',[]):
  if 'bufferView' in a:a['bufferView']=mapping[a['bufferView']]
 doc['bufferViews']=views;doc['buffers'][0]['byteLength']=len(buf)
 encoded=json.dumps(doc,separators=(',',':')).encode()
 encoded+=b' '*((-len(encoded))%4);buf+=b'\0'*((-len(buf))%4)
 body=struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(buf),0x004E4942)+buf
 path.write_bytes(struct.pack('<III',0x46546c67,2,12+len(body))+body)
 print(path.stem,len(raw),'->',path.stat().st_size)

manifest=ROOT/'art/asset-manifest.json'
if manifest.exists():
 records=json.loads(manifest.read_text())
 for item in records:
  file=ROOT/'godot/assets/models'/(item['name']+'.glb')
  if file.exists(): item['runtime_bytes']=file.stat().st_size
 manifest.write_text(json.dumps(records,indent=2)+'\n')
