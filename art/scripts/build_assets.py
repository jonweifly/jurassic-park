"""Original expedition assets. Blender 4.5: --background --python art/scripts/build_assets.py.
Author coordinates are game metres, +Y up, +Z forward. Meshes converted at creation.
No external geometry or textures. Editable sources, UV PBR atlas, skins, baked clips.
"""
import bpy, bmesh, math, random, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from math import sin, cos, pi
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'godot/assets/models'; SRC=ROOT/'art/source'; TEX=ROOT/'art/textures'
for p in (OUT,SRC,TEX): p.mkdir(parents=True,exist_ok=True)
random.seed(650)
# Atlas: 16 authored surface families, each with fine and macro detail.
COLORS=['b6a17b','405748','b7805e','403e32','6b5c42','858a76','9caa9c','ded1a4','66814e','475d34','bd9b48','22302b','a1b5b0','754b35','84928a','dfad52']
N=1024
import numpy as np
rng=np.random.default_rng(650)
y,x=np.mgrid[0:N,0:N]; tile=N//4
pix=np.ones((N,N,4),np.float32); rough=np.ones_like(pix)
for i,c in enumerate(COLORS):
 xx=x[:tile,:tile]; yy=y[:tile,:tile]; noise=rng.random((tile,tile))
 wave=np.sin(xx*.16+np.sin(yy*.04)*3)*np.sin(yy*.08)
 detail=(noise-.5)*.035+wave*.022
 if i in (0,1): detail+=(np.sin(xx*pi)*0.0+((xx%4)==0)*.035+((yy%4)==0)*.025)
 if i in (4,13): detail+=np.sin(xx*.22+np.sin(yy*.037)*1.4)*.10
 if i in (8,9): detail+=(np.cos(xx*.9+np.sin(yy*.4)) *np.cos(yy*.7))*.045
 rgb=np.array([int(c[j:j+2],16)/255 for j in (0,2,4)])
 a,b=(i//4)*tile,(i%4)*tile
 pix[a:a+tile,b:b+tile,:3]=np.clip(rgb[None,None,:]*(1+detail[:,:,None]),0,1)
 rough[a:a+tile,b:b+tile,:3]=np.clip((.58 if i in (6,12,14) else .88)+(noise[:,:,None]-.5)*.10,0,1)
def save_image(name,arr):
 im=bpy.data.images.new(name,width=N,height=N)
 if not name.endswith('albedo'): im.colorspace_settings.name='Non-Color'
 im.pixels.foreach_set(arr.ravel()); im.filepath_raw=str(TEX/(name+'.png')); im.file_format='PNG'; im.save(); return im
# Fine surface normals, low strength so silhouettes and lighting remain readable at RTS zoom.
height=pix[:,:,:3].mean(axis=2); dy,dx=np.gradient(height)
normal=np.ones_like(pix); normal[:,:,0]=np.clip(.5-dx*.8,0,1); normal[:,:,1]=np.clip(.5-dy*.8,0,1); normal[:,:,2]=1
atlas=save_image('expedition_albedo',pix); rmap=save_image('expedition_roughness',rough); normalmap=save_image('expedition_normal',normal)
rmap.colorspace_settings.name='Non-Color'; normalmap.colorspace_settings.name='Non-Color'
def material(name,leaf=False):
 m=bpy.data.materials.new(name); m.use_nodes=True; m.diffuse_color=(.31,.44,.23,1) if leaf else (1,1,1,1)
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Roughness'].default_value=.88
 if leaf:
  attr=m.node_tree.nodes.new('ShaderNodeVertexColor'); attr.layer_name='Color'; m.node_tree.links.new(attr.outputs['Color'],bs.inputs['Base Color'])
 else:
  for im,socket in [(atlas,'Base Color'),(rmap,'Roughness')]:
   tx=m.node_tree.nodes.new('ShaderNodeTexImage'); tx.image=im; m.node_tree.links.new(tx.outputs['Color'],bs.inputs[socket])
  tx=m.node_tree.nodes.new('ShaderNodeTexImage'); tx.image=normalmap
  bump=m.node_tree.nodes.new('ShaderNodeNormalMap'); bump.inputs['Strength'].default_value=.35
  m.node_tree.links.new(tx.outputs['Color'],bump.inputs['Color']); m.node_tree.links.new(bump.outputs['Normal'],bs.inputs['Normal'])
 return m
MAT=material('Expedition_PBR'); LEAF=material('Rainforest_Leaves',True)
def cv(p): return (p[0],-p[2],p[1])
def reset():
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for a in list(bpy.data.actions): bpy.data.actions.remove(a)
 bpy.context.scene.render.fps=30
class Mesh:
 def __init__(self,name,leaf=False): self.name=name; self.v=[]; self.f=[]; self.uv=[]; self.tiles=[]; self.weights=[]; self.leaf=leaf
 def vert(self,p,uv=(0,0),weight=None):
  self.v.append(cv(p)); self.uv.append(uv); self.weights.append(weight or {}); return len(self.v)-1
 def face(self,ids,t=0): self.f.append(tuple(ids)); self.tiles.append(t)
 def loft(self,rings,t=0,n=12,weights=None,axis='y'):
  # rings = center, horizontal radius, second radius. Smooth cross section along anatomical path.
  rows=[]
  for j,(p,rx,rz) in enumerate(rings):
   if axis=='path':
    tangent=Vector(rings[min(j+1,len(rings)-1)][0])-Vector(rings[max(0,j-1)][0]); tangent.normalize()
    ref=Vector((1,0,0)); u=ref-tangent*ref.dot(tangent)
    if u.length<.01: u=Vector((0,0,1)).cross(tangent)
    u.normalize(); v=tangent.cross(u).normalized()
   else: u=Vector((1,0,0)); v=Vector((0,0,1)) if axis=='y' else Vector((0,1,0))
   row=[]
   for k in range(n):
    a=k*2*pi/n; pos=Vector(p)+u*(rx*cos(a))+v*(rz*sin(a))
    row.append(self.vert(pos,(k/n,j/max(1,len(rings)-1)),weights[j] if weights else None))
   rows.append(row)
  for j in range(len(rows)-1):
   for k in range(n): self.face((rows[j][k],rows[j][(k+1)%n],rows[j+1][(k+1)%n],rows[j+1][k]),t)
  self.face(tuple(reversed(rows[0])),t); self.face(rows[-1],t)
 def ellipsoid(self,c,s,t=0,w=None,n=12,r=7):
  rings=[]
  for j in range(r+1):
   a=-pi/2+.02+(pi-.04)*j/r
   rings.append(((c[0],c[1]+s[1]*sin(a),c[2]),s[0]*cos(a),s[2]*cos(a)))
  self.loft(rings,t,n,[w or {}]*(r+1))
 def tube(self,pts,radii,t=4,n=8,w=None): self.loft([(p,r,r) for p,r in zip(pts,radii)],t,n,[w or {}]*len(pts),axis='path')
 def box(self,c,s,t=0,bevel=.025,w=None):
  # Beveled authored box, with octagonal horizontal sections and bevelled end loops.
  sx,sy,sz=s; b=min(bevel,sx*.24,sy*.24,sz*.24); rows=[]
  outline=[(-sx/2+b,-sz/2),(sx/2-b,-sz/2),(sx/2,-sz/2+b),(sx/2,sz/2-b),(sx/2-b,sz/2),(-sx/2+b,sz/2),(-sx/2,sz/2-b),(-sx/2,-sz/2+b)]
  for yy,scale in [(-sy/2,.94),(-sy/2+b,1),(sy/2-b,1),(sy/2,.94)]:
   rows.append([self.vert((c[0]+xx*scale,c[1]+yy,c[2]+zz*scale),(k/8,(yy+sy/2)/sy),w) for k,(xx,zz) in enumerate(outline)])
  for j in range(3):
   for k in range(8): self.face((rows[j][k],rows[j][(k+1)%8],rows[j+1][(k+1)%8],rows[j+1][k]),t)
  self.face(tuple(reversed(rows[0])),t); self.face(rows[-1],t)
 def leafshape(self,c,length,width,angle,tilt=0,t=8):
  # Curved leaf with folded midrib and tapered tip, opaque double-sided geometry.
  d=Vector((cos(angle),tilt,sin(angle))); q=Vector((-sin(angle),0,cos(angle)))
  rows=[]
  for j in range(5):
   f=j/4; mid=Vector(c)+d*length*f+Vector((0,sin(f*pi)*length*.16,0)); span=width*sin(f*pi)**.7
   rows.append([self.vert(mid+q*k*span+Vector((0,-abs(k)*span*.22,0)),(f,(k+1)/2)) for k in (-1,0,1)])
  for j in range(4):
   for k in range(2): self.face((rows[j][k],rows[j+1][k],rows[j+1][k+1],rows[j][k+1]),t)
 def object(self):
  me=bpy.data.meshes.new(self.name); me.from_pydata(self.v,[],self.f); me.update()
  ob=bpy.data.objects.new(self.name,me); bpy.context.collection.objects.link(ob); me.materials.append(LEAF if self.leaf else MAT)
  uv=me.uv_layers.new(name='UVMap'); colors=me.color_attributes.new(name='Color',type='BYTE_COLOR',domain='CORNER') if self.leaf else None
  uv=me.uv_layers['UVMap']  # Creating a color layer can reallocate Blender CustomData; reacquire UV RNA.
  for poly,t in zip(me.polygons,self.tiles):
   poly.use_smooth=True
   for li in poly.loop_indices:
    vi=me.loops[li].vertex_index; u,v=self.uv[vi]; uv.data[li].uv=((t%4+.06+u*.88)/4,(t//4+.06+v*.88)/4)
    if colors:
     base=(.09,.17,.04) if t==9 else (.17,.28,.075); jitter=.85+.3*((vi*31%97)/97)
     colors.data[li].color=(*[z*jitter for z in base],1)
  names={k for w in self.weights for k in w}
  for name in names:
   group=ob.vertex_groups.new(name=name)
   for i,w in enumerate(self.weights):
    if name in w: group.add([i],w[name],'REPLACE')
  # Correct normals coherently after custom loft construction.
  bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(me); bm.free()
  return ob
MAN=[]
def empty(name,p=(0,0,0)):
 ob=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(ob); ob.location=cv(p); return ob
def rig(bones,meshes):
 data=bpy.data.armatures.new('ExpeditionSkeleton'); ob=bpy.data.objects.new('Rig',data); bpy.context.collection.objects.link(ob)
 bpy.context.view_layer.objects.active=ob; ob.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
 for name,a,b,parent in bones:
  bone=data.edit_bones.new(name); bone.head=cv(a); bone.tail=cv(b)
  if parent: bone.parent=data.edit_bones[parent]
 bpy.ops.object.mode_set(mode='OBJECT')
 for m in meshes:
  m.parent=ob; mod=m.modifiers.new('Weighted deformation','ARMATURE'); mod.object=ob
 for b in ob.pose.bones: b.rotation_mode='XYZ'
 ob.select_set(False); return ob

def animate(r,kind):
 human=kind=='survivor'; names=['idle','walk','attack','death']+(['chop','mine','build','carry','carry_idle'] if human else [])
 for name in names:
  duration={'walk':.8,'attack':.8,'death':.8,'chop':1.35,'mine':1.35,'build':.9,'carry':.9}.get(name,2.0)
  end=round(duration*30); action=bpy.data.actions.new(name); r.animation_data_create(); r.animation_data.action=action
  frames=sorted(set(list(range(0,end+1,3))+[end]+([26,33] if name in ('chop','mine') else [])))
  for frame in frames:
   t=frame/30; phase=t/duration; wave=sin(phase*2*pi)
   for b in r.pose.bones: b.rotation_euler=(0,0,0); b.location=(0,0,0)
   def rot(n,x=0,y=0,z=0):
    if n in r.pose.bones: r.pose.bones[n].rotation_euler=(x,y,z)
   if name in ('idle','carry_idle'):
    rot('spine',.025*wave); rot('head',0,.035*wave,0)
    if not human:
     for i in range(3): rot('tail'+str(i),0,0,.07*sin(phase*2*pi-i*.7))
   if name in ('walk','carry'):
    for side,s in [('L',1),('R',-1)]:
     rot('thigh'+side,.63*wave*s); rot('shin'+side,-max(0,-wave*s)*.9); rot('foot'+side,.13*wave*s)
     rot('upper_arm'+side,-.45*wave*s); rot('forearm'+side,-.13-max(0,wave*s)*.2)
    rot('spine',.045,0,.035*wave)
    r.pose.bones['root'].location[1]=abs(wave)*.035
    if not human:
     for i in range(3): rot('tail'+str(i),.03,0,.12*sin(phase*2*pi-i*.6))
   if name in ('carry','carry_idle'):
    rot('upper_armL',-1.05,0,-.14); rot('upper_armR',-1.05,0,.14); rot('forearmL',-.7); rot('forearmR',-.7)
   if name in ('chop','mine','build'):
    contact=.65 if name=='build' else 1.1; wind=.48 if name=='build' else .85
    if t<=wind: a=-.45-1.85*sin(t/wind*pi/2)
    elif t<=contact: a=-2.3+1.4*((t-wind)/(contact-wind))**.7
    else: a=-.9+.35*(t-contact)/(duration-contact)
    rot('upper_armR',a,0,.12); rot('forearmR',-.4 if t<wind else -.18); rot('handR',.15)
    rot('upper_armL',a*.55,0,-.18); rot('forearmL',-.65); rot('spine',.10+max(0,a+1)*.18,0,.08*sin(phase*pi)); rot('head',-.1)
    if human:
     load=min(1,t/wind); hit=max(0,min(1,(t-wind)/(contact-wind))); release=max(0,min(1,(t-contact)/(duration-contact)))
     tension=sin(load*pi/2)*(1-hit); drive=hit*(1-release)
     if name=='mine':
      rot('upper_armR',a-.14*tension,0,.06); rot('upper_armL',a*.78,0,-.06)
      rot('forearmL',-.52); rot('spine',.10-.12*tension+.22*drive,0,.02*tension)
      rot('head',-.10+.08*tension)
     elif name=='chop':
      rot('spine',.10+.09*drive,0,.08*tension-.04*drive)
      rot('upper_armL',a*.70,0,-.12); rot('forearmL',-.55)
     else:
      # The free arm braces the body while the shorter hammer stroke stays one-handed.
      rot('upper_armR',a*.85,0,.08); rot('forearmR',-.28)
      rot('upper_armL',-.28,0,-.20); rot('forearmL',-.45)
      rot('spine',.12+.07*drive,0,.025*tension)
   if name=='attack':
    strike=sin(min(1,phase/.65)*pi)
    if human: rot('upper_armR',-1.25+strike*.12); rot('forearmR',-.4); rot('upper_armL',-1.1,0,-.3); rot('forearmL',-.9)
    else:
     rot('spine',.18*strike); rot('neck',.35*strike); rot('head',-.15*strike); rot('jaw',-.55*strike)
     for i in range(3): rot('tail'+str(i),-.12*strike)
   if name=='death':
    f=min(1,phase*1.3); rot('root',0,0,1.48*f); r.pose.bones['root'].location[1]=-.78*f if human else -.68*f
    rot('thighL',.5*f); rot('shinR',-.9*f); rot('head',.4*f)
   if name in ('walk','carry'):
    # Two-bone sagittal IK authored offline. One foot supports the body throughout
    # the cycle; feet stay horizontal instead of rotating with the shin.
    r.pose.bones['root'].location[1]=-.075 if human else -.025
    bpy.context.view_layer.update()
    for side,sign in [('L',-1),('R',1)]:
     cycle=(phase+(0 if side=='L' else .5))%1
     stride=.34 if human else .43
     if cycle<.5:
      z=stride*(1-cycle*4); lift=0
     else:
      f=(cycle-.5)*2; z=-stride+2*stride*(f*f*(3-2*f)); lift=(.16 if human else .20)*sin(f*pi)
     upper=r.pose.bones['thigh'+side]; lower=r.pose.bones['shin'+side]; foot=r.pose.bones['foot'+side]
     hip=upper.head.copy()
     restfoot=r.data.bones['foot'+side].head_local.copy()
     target=Vector((restfoot.x,restfoot.y-z,restfoot.z+lift-.004))
     delta=target-hip; dist=min(delta.length,upper.length+lower.length-.002); axis=delta.normalized()
     along=(upper.length**2-lower.length**2+dist**2)/(2*dist)
     bend=Vector((0,-1,0)); bend=(bend-axis*axis.dot(bend)).normalized()
     knee=hip+axis*along+bend*math.sqrt(max(.00001,upper.length**2-along**2))
     for bone,start,endpoint in [(upper,hip,knee),(lower,knee,target)]:
      rest=r.data.bones[bone.name]; direction=(endpoint-start).normalized()
      rotation=(rest.tail_local-rest.head_local).normalized().rotation_difference(direction) @ rest.matrix_local.to_quaternion()
      bone.matrix=Matrix.Translation(start) @ rotation.to_matrix().to_4x4()
      bpy.context.view_layer.update()
     foot.matrix=Matrix.Translation(target) @ r.data.bones[foot.name].matrix_local.to_quaternion().to_matrix().to_4x4()
     bpy.context.view_layer.update()
   for b in r.pose.bones:
    b.keyframe_insert('rotation_euler',frame=frame); b.keyframe_insert('location',frame=frame)
  # One action per NLA track: stable glTF clip names, no accidental concatenation.
  track=r.animation_data.nla_tracks.new(); track.name=name; strip=track.strips.new(name,0,action); strip.action_frame_start=0; strip.action_frame_end=end
  r.animation_data.action=None; track.mute=True
 r.animation_data.action=None
 for b in r.pose.bones: b.rotation_euler=(0,0,0); b.location=(0,0,0)
 bpy.context.scene.frame_set(0)

def export(name):
 bpy.ops.object.select_all(action='SELECT')
 bpy.context.scene.frame_set(0)
 for im in (atlas,rmap,normalmap): im.filepath='//../textures/'+im.name+'.png'
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')),compress=True)
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_skins=True,export_tangents=True,export_apply=False,export_cameras=False,export_lights=False)
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']; rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
 tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
 MAN.append(dict(name=name,triangles=tris,meshes=len(meshes),bones=sum(len(r.data.bones) for r in rigs),clips=[a.name for a in bpy.data.actions],bytes=(OUT/(name+'.glb')).stat().st_size))
 manifest=ROOT/'art/asset-manifest.json'
 old=json.loads(manifest.read_text()) if manifest.exists() else []
 manifest.write_text(json.dumps([x for x in old if x['name']!=name]+[MAN[-1]],indent=2)+'\n')
 print('ASSET',name,tris,flush=True)

def survivor():
 reset(); m=Mesh('Survivor_Surface')
 bones=[('root',(0,.96,0),(0,1.1,0),None),('spine',(0,1.05,0),(0,1.46,0),'root'),('neck',(0,1.46,0),(0,1.6,0),'spine'),('head',(0,1.6,0),(0,1.86,0),'neck')]
 m.loft([((0,.94,0),.24,.14),((0,1.04,0),.23,.15),((0,1.2,0),.24,.15),((0,1.4,0),.29,.17),((0,1.48,0),.27,.14),((0,1.54,0),.11,.09)],0,16,[{'root':1},{'root':.8,'spine':.2},{'spine':1},{'spine':1},{'spine':1},{'neck':1}])
 m.loft([((0,1.5,0),.08,.08),((0,1.64,0),.085,.08)],2,12,[{'neck':1}]*2)
 m.loft([((0,1.61,.015),.08,.085),((0,1.66,.02),.115,.115),((0,1.73,0),.135,.135),((0,1.82,-.008),.13,.13),((0,1.88,-.02),.09,.09)],2,16,[{'head':1}]*5)
 m.ellipsoid((0,1.745,.133),(.033,.042,.036),2,{'head':1},10,5)
 for s in (-1,1):
  m.ellipsoid((s*.135,1.75,0),(.028,.048,.025),2,{'head':1},8,5)
  m.ellipsoid((s*.063,1.778,.123),(.038,.014,.018),11,{'head':1},10,4)
  m.tube([(s*.032,1.797,.128),(s*.096,1.796,.111)],[.009,.008],3,5,{'head':1})
 m.tube([(-.047,1.683,.113),(0,1.678,.124),(.047,1.683,.113)],[.007]*3,13,5,{'head':1})
 # Tailored vest panels, seams, pockets and harness attached to chest.
 for s in (-1,1):
  m.box((s*.143,1.295,.161),(.24,.36,.052),1,.023,{'spine':1})
  m.box((s*.15,1.19,.199),(.16,.11,.065),4,.015,{'spine':1})
  m.tube([(s*.18,1.09,.2),(s*.21,1.44,.18),(s*.19,1.48,-.1),(s*.17,1.13,-.21)],[.026]*4,3,6,{'spine':1})
 m.box((0,1.29,-.22),(.37,.38,.18),1,.05,{'spine':1}); m.box((0,1.14,-.31),(.30,.12,.08),4,.02,{'spine':1})
 m.loft([((0,1.0,0),.244,.16),((0,1.055,0),.244,.16)],3,16,[{'root':1}]*2)
 m.box((0,1.028,.166),(.073,.054,.025),6,.007,{'root':1})
 m.loft([((0,1.86,-.01),.17,.15),((0,1.9,-.01),.155,.14),((0,1.98,-.02),.12,.115)],1,18,[{'head':1}]*3)
 m.loft([((0,1.864,.02),.247,.23),((0,1.882,.02),.244,.23)],4,22,[{'head':1}]*2)
 for side,s in [('L',-1),('R',1)]:
  hip=(s*.13,.99,0); knee=(s*.14,.55,.015); ankle=(s*.14,.15,0)
  shoulder=(s*.29,1.45,0); elbow=(s*.37,1.17,.015); wrist=(s*.4,.94,.05)
  bones += [('thigh'+side,hip,knee,'root'),('shin'+side,knee,ankle,'thigh'+side),('foot'+side,ankle,(s*.14,.09,.23),'shin'+side),('upper_arm'+side,shoulder,elbow,'spine'),('forearm'+side,elbow,wrist,'upper_arm'+side),('hand'+side,wrist,(s*.4,.86,.065),'forearm'+side)]
  m.loft([(hip,.125,.14),((s*.14,.82,0),.12,.125),((s*.14,.62,.01),.092,.095),(knee,.083,.09),((s*.14,.46,.005),.09,.10),((s*.14,.28,0),.073,.077),(ankle,.063,.065)],1,12,[{'thigh'+side:1},{'thigh'+side:1},{'thigh'+side:.85,'shin'+side:.15},{'thigh'+side:.5,'shin'+side:.5},{'shin'+side:1},{'shin'+side:1},{'shin'+side:1}])
  m.ellipsoid((s*.14,.095,.09),(.098,.09,.20),3,{'foot'+side:1},12,6)
  m.box((s*.14,.036,.07),(.19,.055,.34),11,.016,{'foot'+side:1})
  m.box((s*.237,.78,0),(.065,.16,.14),4,.02,{'thigh'+side:1})
  m.loft([(shoulder,.116,.115),((s*.33,1.36,0),.105,.105),((s*.355,1.26,.01),.089,.092)],0,12,[{'upper_arm'+side:1}]*3)
  m.loft([((s*.354,1.28,.01),.075,.074),(elbow,.066,.065),((s*.385,1.07,.028),.069,.068),(wrist,.045,.044)],2,12,[{'upper_arm'+side:1},{'upper_arm'+side:.5,'forearm'+side:.5},{'forearm'+side:1},{'forearm'+side:1}])
  m.ellipsoid((s*.402,.896,.058),(.052,.071,.042),2,{'hand'+side:1},10,5)
  for j in range(3): m.tube([(s*.39+(j-1)*.018,.88,.086),(s*.39+(j-1)*.018,.852,.08)],[.012,.01],2,5,{'hand'+side:1})
 # Close-up readability pass: small field details sit on the same weighted
 # surface as the body, so they follow the authored clips instead of floating
 # as static props when the camera is zoomed in.
 m.box((0,1.455,.205),(.23,.11,.035),4,.012,{'spine':1})
 m.tube([(0,1.12,.197),(0,1.32,.196),(0,1.45,.188)],[.007]*3,3,5,{'spine':1})
 for s in (-1,1):
  side='L' if s<0 else 'R'
  m.tube([(s*.09,1.515,.07),(s*.14,1.46,.15),(s*.065,1.435,.175)],[.015,.019,.011],0,6,{'spine':1})
  m.loft([((s*.353,1.285,.01),.092,.094),((s*.357,1.25,.01),.09,.093)],4,12,[{'upper_arm'+side:1}]*2)
 for s in (-1,1):
  m.box((s*.18,1.30,.235),(.105,.14,.06),4,.014,{'spine':1})
  m.box((s*.135,1.00,.155),(.075,.09,.06),11,.012,{'root':1})
  m.ellipsoid((s*.14,.555,.085),(.075,.065,.026),11,{'thigh'+('L' if s < 0 else 'R'):.5,'shin'+('L' if s < 0 else 'R'):.5},10,5)
 # A low-profile headset and radio mic give the survivor a recognizable
 # silhouette without changing the expedition palette or adding a second mesh.
 m.box((.108,1.735,.02),(.026,.055,.045),11,.008,{'head':1})
 m.tube([(.11,1.72,.025),(.145,1.70,.12),(.065,1.69,.157)],[.009,.008,.007],11,5,{'head':1})
 ob=m.object(); r=rig(bones,[ob]); animate(r,'survivor'); export('survivor')

def dinosaur(name):
 reset(); rex=name=='trex'; m=Mesh('Tyrannosaur_Surface' if rex else 'Raptor_Surface'); c=13 if rex else 8
 # Long low torso and counterbalancing tail, digitigrade limbs, sculpted skull and separate jaw.
 bones=[('root',(0,1.0,-.22),(0,1.22,-.05),None),('spine',(0,1.2,-.22),(0,1.46,.48),'root'),('neck',(0,1.46,.48),(0,1.85,.81),'spine'),('head',(0,1.85,.81),(0,1.9,1.43),'neck'),('jaw',(0,1.73,.84),(0,1.72,1.45),'head'),('tail0',(0,1.18,-.6),(0,1.09,-1.35),'root'),('tail1',(0,1.09,-1.35),(0,1.19,-2.1),'tail0'),('tail2',(0,1.19,-2.1),(0,1.4,-2.95),'tail1')]
 width=1.30 if rex else 1
 m.loft([((0,1.17,-.75),.15*width,.18),((0,1.2,-.5),.34*width,.4),((0,1.25,-.1),.38*width,.43),((0,1.4,.29),.29*width,.32),((0,1.5,.52),.18*width,.25),((0,1.72,.66),.14*width,.24),((0,1.84,.87),.16*width,.19)],c,18,[{'root':1},{'root':1},{'root':.5,'spine':.5},{'spine':1},{'spine':.6,'neck':.4},{'neck':1},{'neck':.3,'head':.7}],axis='z')
 # Flattened cranium with orbital ridge and tapered muzzle.
 m.loft([((0,1.9,.77),.17*width,.18),((0,1.95,.94),.23*width,.22 if rex else .16),((0,1.92,1.14),.19*width,.17 if rex else .12),((0,1.88,1.46),.16*width,.115),((0,1.86,1.58),.13*width,.09)],c,16,[{'head':1}]*5,axis='z')
 m.loft([((0,1.73,.82),.15*width,.08),((0,1.71,1.04),.18*width,.075),((0,1.735,1.48),.13*width,.048)],7,12,[{'jaw':1}]*3,axis='z')
 m.loft([((0,1.18,-.64),.20*width,.19),((0,1.10,-1.0),.16*width,.145),((0,1.09,-1.35),.12,.11),((0,1.14,-1.74),.087,.08),((0,1.23,-2.1),.06,.06),((0,1.33,-2.53),.037,.035),((0,1.40,-2.96),.007,.009)],c,12,[{'root':.5,'tail0':.5},{'tail0':1},{'tail0':.5,'tail1':.5},{'tail1':1},{'tail1':.5,'tail2':.5},{'tail2':1},{'tail2':1}],axis='z')
 for s,side in [(-1,'L'),(1,'R')]:
  hip=(s*.30*width,1.23,-.19); knee=(s*.4*width,.75,.10); hock=(s*.39*width,.34,-.18); toe=(s*.39*width,.10,.35)
  sh=(s*.24*width,1.47,.42); elbow=(s*(.34 if rex else .4),1.17,.65); hand=(s*.38,1.18,.86 if not rex else .72)
  bones += [('thigh'+side,hip,knee,'root'),('shin'+side,knee,hock,'thigh'+side),('foot'+side,hock,toe,'shin'+side),('upper_arm'+side,sh,elbow,'spine'),('forearm'+side,elbow,hand,'upper_arm'+side),('hand'+side,hand,(hand[0],hand[1]-.07,hand[2]+.08),'forearm'+side)]
  m.loft([(hip,.23*width,.27),((s*.4*width,.98,.04),.2*width,.20),(knee,.115,.13),((s*.4*width,.58,-.06),.09,.095),(hock,.062,.07),(toe,.065,.10)],c,14,[{'thigh'+side:1},{'thigh'+side:1},{'thigh'+side:.45,'shin'+side:.55},{'shin'+side:1},{'shin'+side:.5,'foot'+side:.5},{'foot'+side:1}],axis='path')
  for j in range(3):
   x=s*.39*width+(j-1)*.075
   m.tube([(s*.39*width,.12,.05),(x,.085,.32),(x+(j-1)*.02,.065,.5)],[.045,.034,.012],c,7,{'foot'+side:1})
   m.tube([(x,.07,.43),(x,.095,.51),(x,.055,.57)],[.031,.021,.002],11,7,{'foot'+side:1})
  if not rex: m.tube([(s*.31,.14,.23),(s*.30,.28,.33),(s*.30,.27,.42),(s*.30,.17,.46)],[.045,.037,.018,.002],11,8,{'foot'+side:1})
  m.loft([(sh,.078,.095),(elbow,.048,.052),(hand,.038,.04)],c,10,[{'upper_arm'+side:1},{'upper_arm'+side:.4,'forearm'+side:.6},{'hand'+side:1}],axis='path')
  for j in range(2 if rex else 3):
   x=hand[0]+(j-1)*.033; m.tube([(x,hand[1],hand[2]),(x,hand[1]-.07,hand[2]+.13),(x,hand[1]-.13,hand[2]+.14)],[.018,.012,.001],11,6,{'hand'+side:1})
  m.ellipsoid((s*.213*width,2.005,.983),(.032,.044,.063),10,{'head':1},12,6)
  m.ellipsoid((s*.240*width,2.007,.996),(.009,.029,.018),11,{'head':1},10,5)
  m.tube([(s*.19*width,2.06,.89),(s*.24*width,2.055,1.04),(s*.19*width,2.0,1.14)],[.031,.041,.025],c,8,{'head':1})
  m.ellipsoid((s*.14*width,1.9,1.49),(.016,.023,.033),11,{'head':1},8,5)
  for j in range(8):
   z=.99+j*.065; x=s*(.17-(z-1)*.065)*width
   m.tube([(x,1.805,z),(x,1.736,z+.011)],[.018,.001],7,6,{'head':1})
  # Irregular dorsal banding modeled flush into body silhouette, no floating cubes.
  # Skin banding is authored into surface UV tile choice below.
 # Dark transverse skin bands along the back, integrated with the surface.
 for i,f in enumerate(m.f):
  if m.tiles[i]!=c: continue
  pts=[m.v[v] for v in f]; zz=-sum(p[1] for p in pts)/len(pts); yy=sum(p[2] for p in pts)/len(pts)
  if -.65<zz<.4 and yy>1.36 and sin(zz*25+yy*2)>.5: m.tiles[i]=4 if rex else 9
 if rex:
  # Distinct deep skull, thicker neck, heavy chest and tiny forelimbs.
  def shape(p,head=False,arm=False):
   x,y,z=p
   if head: return (x*1.36,1.80+(y-1.80)*1.45,z+.15)
   if arm: return (x*.84,1.42+(y-1.42)*.60,.48+(z-.48)*.62)
   return p
  for i,p in enumerate(m.v):
   w=m.weights[i]; head=bool(set(w)&{'head','jaw'}); arm=any('arm' in b or 'hand' in b for b in w)
   m.v[i]=cv(shape((p[0],p[2],-p[1]),head,arm))
  bones=[(n,shape(a,n in ('head','jaw'),('arm' in n or 'hand' in n)),shape(b,n in ('neck','head','jaw'),('arm' in n or 'hand' in n)),parent) for n,a,b,parent in bones]
 r=rig(bones,[m.object()]); animate(r,name); export(name)

def tree(name):
 print('TREE START',name,flush=True)
 reset(); low=name.endswith('_lod'); family=name.replace('_lod',''); snow=family=='snow_tree'; conifer=family in ('tree','snow_tree'); bark=Mesh('Trunk'); rng=random.Random(188 if conifer else 90)
 pts=[(0,0,0),(.05,.45,0),(-.08,1.2,.04),(.06,2.0,.0),(.12,2.9,.06),(.03,3.8,.0),(.12,4.6,.03)]
 bark.tube(pts,[.31,.23,.18,.14,.10,.06,.01],14 if snow else 4,10)
 for k in range(6):
  a=k*pi/3+.2; bark.tube([(0,.45,0),(cos(a)*.38,.12,sin(a)*.38),(cos(a)*.83,.02,sin(a)*.83)],[.15,.1,.009],4,6)
 crowns=[Mesh('Crown',True),Mesh('Left',True),Mesh('Top',True)]
 if conifer:
  for tier in range(6):
   h=1.35+tier*.51; radius=1.5-tier*.2
   for j in range(6):
    a=j*2*pi/6+tier*.71; tip=(cos(a)*radius,h+.10,sin(a)*radius)
    bark.tube([(0,h+.22,0),tip],[.045,.007],4,5)
    for k in range(3):
     f=.25+k*.27; c=(tip[0]*f,h+.25-f*.15,tip[2]*f)
     for off in ((0,) if low else (-.5,.5)):
      if not low or k%2==0: crowns[tier%3].leafshape(c,.65*(1-tier*.065) if low else .5*(1-tier*.065),.29 if low else .22,a+off,.1,8 if (j+k)%3 else 9)
 else:
  for j in range(10):
   a=j*2.4; h=2.0+(j%4)*.45; radius=1.15+(j%3)*.23; tip=(cos(a)*radius,h+.72,sin(a)*radius)
   bark.tube([(.04,h-.7,0),(cos(a)*radius*.45,h+.05,sin(a)*radius*.45),tip],[.105,.058,.012],4,7)
   for k in range(17):
    theta=rng.random()*2*pi; rad=rng.random()**.5*.65
    c=(tip[0]+cos(theta)*rad,tip[1]+rng.uniform(-.3,.3),tip[2]+sin(theta)*rad)
    length=rng.uniform(.42,.78); width=rng.uniform(.16,.28); tilt=rng.uniform(-.2,.4)
    if not low or k%3==0: crowns[j%3].leafshape(c,length*(1.3 if low else 1),width*(1.4 if low else 1),theta,tilt,9 if k%3==0 else 8)
 print('TREE BARK',len(bark.v),flush=True)
 bark.object()
 print('TREE BARK DONE',flush=True)
 for crown in crowns:
  print('CROWN',crown.name,len(crown.v),flush=True)
  ob=crown.object()
  print('CROWN DONE',flush=True)
  # Deterministic offline simplification: keep many recognizable curved leaves, budget repeated canopy.
  # Opaque leaf ribbons are already budgeted; degenerate pointed tips are not decimated here.
  # Godot generates surface LODs during import.
  if snow:
   for color in ob.data.color_attributes['Color'].data:
    c=color.color; color.color=(c[0]*.4+.48,c[1]*.4+.55,c[2]*.4+.51,1)
 export(name)

def tent():
 reset(); base=Mesh('Foundation'); canvas=Mesh('Canvas'); frame=Mesh('Frame'); props=Mesh('CampKit')
 for j in range(9): base.box((-.88+j*.22,.065,0),(.208,.13,1.88),4,.012)
 # Catenary sag, raised ridge, open entrance, sewn seams; actual two-sided thickness.
 for s in (-1,1):
  rows=[]
  for j in range(13):
   z=-.86+j*1.72/12; row=[]
   for k in range(11):
    f=k/10; xx=s*(.025+f*.87); yy=1.82-f*1.33-.075*sin(f*pi)*cos(z*1.1)+.018*sin(z*24)*sin(f*pi)
    row.append(canvas.vert((xx,yy,z),(f,j/12)))
   rows.append(row)
  for j in range(12):
   for k in range(10): canvas.face((rows[j][k],rows[j+1][k],rows[j+1][k+1],rows[j][k+1]),0)
  # Entrance side curtain folds; central passage stays visibly open.
  for side in (-1,1):
   ids=[canvas.vert((s*.04,1.79,side*.86),(0,0)),canvas.vert((s*.88,.46,side*.86),(1,1)),canvas.vert((s*.48,.19,side*.89),(.7,1)),canvas.vert((s*.34,1.04,side*.90),(.3,.4))]
   canvas.face(ids,0)
  for z in (-.86,-.3,.3,.86): frame.tube([(0,1.84,z),(s*.46,1.11,z),(s*.90,.48,z)],[.012]*3,7,5)
  for z in (-.77,.77):
   frame.tube([(s*.87,.51,z),(s*.98,.04,z+.13*s)],[.009]*2,7,5)
   frame.tube([(s*.98,.16,z+.13*s),(s*.98,0,z+.13*s)],[.019]*2,6,6)
 for z in (-.8,.78): frame.tube([(0,.13,z),(0,1.80,z)],[.025]*2,4,8)
 frame.tube([(0,1.81,-.94),(0,1.81,.95)],[.032]*2,4,8)
 props.box((-.43,.20,-.20),(.52,.13,.9),1,.05)
 props.ellipsoid((-.44,.27,-.50),(.24,.08,.18),0,n=12,r=5)
 props.box((.52,.22,.44),(.35,.30,.36),4,.02)
 for x in (.39,.64): props.box((x,.22,.44),(.025,.31,.37),6,.004)
 for m in (base,canvas,frame,props):
  ob=m.object()
  if m==canvas:
   mod=ob.modifiers.new('Sewn fabric thickness','SOLIDIFY'); mod.thickness=.012; bpy.context.view_layer.objects.active=ob; bpy.ops.object.modifier_apply(modifier=mod.name)
 export('tent')

def prop(name):
 reset(); m=Mesh('Surface')
 if name in ('axe','pickaxe','hammer'):
  # Palm origin, head extends along local game +Z.
  m.tube([(0,0,-.13),(.018,0,.18),(0,0,.55)],[.035,.032,.026],4,10)
  if name=='axe':
   m.loft([((0,0,.48),.044,.075),((0,0,.57),.06,.08),((0,0,.64),.042,.16),((0,0,.69),.014,.18)],6,8,axis='z')
  elif name=='pickaxe': m.tube([(-.37,.02,.60),(-.19,.06,.63),(0,.07,.60),(.20,.03,.58),(.35,-.03,.53)],[.003,.026,.05,.025,.001],6,8)
  else: m.box((0,0,.57),(.32,.16,.16),6,.025)
  for z in (-.10,-.05,0,.05): m.tube([(-.027,-.012,z),(.027,-.012,z)],[.013,.013],3,6)
 elif name=='rifle':
  m.box((0,.035,.23),(.08,.13,.38),6,.015); m.box((0,.015,-.05),(.07,.13,.20),4,.02)
  m.tube([(0,.08,.36),(0,.08,.81)],[.024,.019],11,10); m.box((0,-.055,.11),(.065,.16,.13),11,.012)
  m.tube([(0,.16,.12),(0,.16,.35)],[.035,.035],11,10)
 elif name=='wood_cargo':
  for i in range(4):
   y=(i//2)*.13; z=(i%2)*.15
   m.tube([(-.36,y,z),(.34,y,z)],[.079,.072],4,10)
  for x in (-.20,.20): m.tube([(x,-.07,-.07),(x,.23,-.07),(x,.23,.23),(x,-.07,.23),(x,-.07,-.07)],[.015]*5,7,5)
 elif name=='ore_cargo':
  m.box((0,-.12,0),(.55,.08,.32),4,.012)
  for x in (-.26,.26): m.box((x,-.04,0),(.04,.24,.33),4,.008)
  for i in range(5): m.ellipsoid((-.18+i*.085,.015+(i%2)*.045,0),(.095,.08,.12),10 if i%2 else 14,n=7,r=4)
 m.object(); export(name)

def rock():
 reset(); m=Mesh('StratifiedRock'); rng=random.Random(555)
 for c,s in [((-.15,.45,0),(.86,.72,.65)),((.68,.22,.22),(.52,.36,.46)),((-.60,.17,.53),(.35,.28,.35))]:
  start=len(m.v); m.ellipsoid(c,s,14,n=11,r=6)
  for i in range(start,len(m.v)):
   p=Vector(m.v[i]); p+=Vector([rng.uniform(-.06,.06) for _ in range(3)]); p.z=max(0,p.z); m.v[i]=p
 ob=m.object()
 for p in ob.data.polygons: p.use_smooth=False
 export('rock')

def fern():
 reset(); m=Mesh('Foliage',True); stem=Mesh('Stem')
 for j in range(8):
  a=j*pi/4; pts=[]
  for k in range(9):
   f=k/8; c=(cos(a)*f*.68,.08+sin(f*pi*.78)*.43,sin(a)*f*.68); pts.append(c)
   if k in (0,8): continue
   for s in (-1,1): m.leafshape(c,.20*sin(f*pi)+.06,.04,a+s*1.05,-.2,9 if j%3 else 8)
  stem.tube(pts,[.013*(1-k/10) for k in range(9)],9,5)
 stem.object(); m.object(); export('fern')

def buildings(name):
 reset(); base=Mesh('Foundation'); body=Mesh('Structure'); detail=Mesh('Details')
 if name=='fire':
  for i in range(12):
   a=i*2*pi/12; base.ellipsoid((cos(a)*.61,.13,sin(a)*.61),(.18,.14,.16),14,n=8,r=5)
  for a in (0,1.1,2.4): body.tube([(cos(a)*-.45,.18,sin(a)*-.45),(cos(a)*.45,.20,sin(a)*.45)],[.085,.075],13,9)
  for name2,h,r in [('Flame',.85,.28),('FlameCore',.56,.18)]:
   f=Mesh(name2); f.loft([((0,.22,0),r,r),((.07,.44,.03),r*.7,r*.6),((-.04,h,0),.006,.006)],15,8); f.object()
 elif name in ('shelter','gate'):
  for x in (-.85,.85):
   base.box((x,.075,0),(.24,.15,.3),14,.025); body.tube([(x,.1,0),(x,1.72,0)],[.047,.044],6,8)
   for y in (.45,.9,1.4): body.ellipsoid((x,y,0),(.082,.055,.07),12,n=10,r=4)
  leaf=Mesh('FencePanel')
  for y in (.45,.9,1.4): leaf.tube([(-.82,y,0),(.82,y,0)],[.014,.014],6,6)
  for x in [-.70+i*.17 for i in range(9)]: leaf.tube([(x,.39,0),(x,1.45,0)],[.007,.007],6,5)
  leaf.box((0,1.07,.02),(.32,.32,.05),10,.015)
  # Hazard lightning bolt made of thin solid ribbon.
  ids=[leaf.vert(p) for p in [(.02,1.19,.049),(-.065,1.04,.049),(.005,1.04,.049),(-.02,.96,.049),(.085,1.10,.049),(.02,1.10,.049)]]; leaf.face(ids,11)
  ob=leaf.object()
  if name=='gate':
   pivot=empty('Leaf',(-.85,0,0)); ob.parent=pivot; ob.location=cv((.85,0,0))
 elif name=='generator':
  base.box((0,.10,0),(1.65,.20,1.48),14,.035)
  for x in (-.63,.63): body.tube([(x,.23,-.53),(x,1.19,-.53),(x,1.19,.53),(x,.23,.53)],[.043]*4,6,8)
  body.box((0,.66,0),(1.13,.79,.92),1,.085)
  body.loft([((0,.39,-.55),.36,.32),((0,.39,-.30),.36,.32)],6,16,axis='z')
  for x in [-.4+i*.10 for i in range(9)]: detail.box((x,.66,.471),(.046,.43,.025),11,.005)
  detail.box((0,1.085,0),(.84,.06,.6),4,.015)
  detail.box((.581,.80,.10),(.027,.24,.36),11,.008)
  for z in (0,.14): detail.ellipsoid((.604,.85,z),(.014,.055,.045),12,n=10,r=5)
  body.tube([(-.4,.91,-.27),(-.4,1.47,-.27),(-.4,1.5,-.46)],[.055]*3,6,10)
  for z in (-.4,.4): detail.box((0,.18,z),(1.25,.055,.08),3,.01)
 elif name=='tower':
  base.box((0,.09,0),(1.70,.18,1.7),14,.03)
  for x in (-.58,.58):
   for z in (-.58,.58): body.tube([(x,.17,z),(x*.85,1.8,z*.85)],[.073,.059],4,8)
   body.tube([(x,.3,-.55),(x,1.55,.52)],[.032]*2,4,6); body.tube([(x,.3,.55),(x,1.55,-.52)],[.032]*2,4,6)
  for i in range(8): detail.box((-.7+i*.2,1.78,0),(.19,.09,1.52),4,.009)
  for y in [.3+i*.24 for i in range(6)]: body.tube([(-.22,y,-.69),(.22,y,-.69)],[.023]*2,6,6)
  gun=Mesh('Ballista'); gun.box((0,.1,.15),(.16,.18,.78),4,.025)
  gun.tube([(-.64,.15,.27),(-.3,.19,.47),(0,.2,.51),(.3,.19,.47),(.64,.15,.27)],[.04,.045,.05,.045,.04],4,8)
  gun.tube([(-.64,.15,.27),(0,.17,-.2),(.64,.15,.27)],[.008]*3,7,5)
  gun.tube([(0,.24,-.38),(0,.24,.87)],[.022,.014],6,8)
  ob=gun.object(); pivot=empty('Gun',(0,1.86,0)); ob.parent=pivot
 elif name=='lab':
  base.box((0,.12,0),(1.90,.24,1.90),14,.03)
  body.box((0,.99,0),(1.68,1.5,1.66),0,.055)
  body.box((0,1.79,0),(1.90,.15,1.90),1,.05)
  for x in (-.80,.80):
   for z in (-.79,.79): detail.box((x,1.0,z),(.065,1.47,.065),6,.008)
  detail.box((0,.82,.845),(.50,1.05,.06),1,.02)
  for x in (-.56,.56):
   detail.box((x,1.23,.85),(.40,.44,.045),11,.014); detail.box((x,1.23,.88),(.34,.37,.02),12,.008)
   detail.box((x,1.23,.897),(.018,.37,.015),6,.003)
  detail.ellipsoid((.16,.80,.885),(.025,.025,.016),6,n=8,r=4)
  for i in range(5): detail.box((-.849,1.04+i*.07,-.1),(.028,.025,.55),11,.002)
  body.tube([(.46,1.85,-.40),(.46,2.15,-.40)],[.027,.024],6,8)
  # Concave satellite dish profile (not a cone placeholder).
  detail.loft([((.46,2.11,-.4),.05,.05),((.46,2.14,-.4),.13,.13),((.46,2.22,-.4),.29,.29),((.46,2.30,-.4),.36,.36)],12,20)
  detail.tube([(.46,2.12,-.4),(.46,2.47,-.4)],[.015,.012],6,7)
 elif name=='fossil':
  base.ellipsoid((0,.025,0),(1.02,.11,.86),13,n=16,r=5)
  for j in range(7):
   x=-.54+j*.16; points=[(x,.13,-.5),(x,.29,-.32),(x,.34,0),(x,.29,.31),(x,.1,.5)]
   body.tube(points,[.035]*5,7,7)
  body.tube([(-.68,.32,0),(.66,.32,0)],[.05,.04],7,9)
  body.ellipsoid((.70,.26,.01),(.24,.18,.23),7,n=12,r=6)
  for z in (-.16,.16): detail.ellipsoid((.73,.30,z),(.10,.068,.016),11,n=8,r=4)
  for x in (-.8,.8):
   for z in (-.65,.65): detail.tube([(x,0,z),(x,.5,z)],[.018,.016],4,6)
  detail.tube([(-.8,.43,-.65),(.8,.43,-.65),(.8,.43,.65),(-.8,.43,.65),(-.8,.43,-.65)],[.01]*5,7,5)
 for m in (base,body,detail):
  if m.v: m.object()
 export(name)

if __name__=='__main__':
 requested=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
 jobs=[('survivor',survivor),('raptor',lambda:dinosaur('raptor')),('broadleaf',lambda:tree('broadleaf')),('tent',tent),('trex',lambda:dinosaur('trex')),('tree',lambda:tree('tree')),('snow_tree',lambda:tree('snow_tree')),('rock',rock),('fern',fern)]
 jobs += [(n,lambda n=n:tree(n)) for n in ['broadleaf_lod','tree_lod','snow_tree_lod']]
 jobs += [(n,lambda n=n:prop(n)) for n in ['axe','pickaxe','hammer','rifle','wood_cargo','ore_cargo']]
 jobs += [(n,lambda n=n:buildings(n)) for n in ['fire','generator','shelter','gate','tower','lab','fossil']]
 for name,job in jobs:
  if not requested or name in requested: job()
 manifest=ROOT/'art/asset-manifest.json'
 if requested and manifest.exists(): MAN=[x for x in json.loads(manifest.read_text()) if x['name'] not in requested]+MAN
 manifest.write_text(json.dumps(MAN,indent=2)+'\n')
