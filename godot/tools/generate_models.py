"""Create editable native Godot blockout scenes; no third-party art assets."""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]/'scenes'/'models'
ROOT.mkdir(parents=True, exist_ok=True)
class Scene:
 def __init__(self,name,pawn=False):
  self.name=name;self.pawn=pawn;self.resources=[];self.nodes=[];self.ids=0;self.materials={}
  self.node('Model','Node3D','.')
 def res(self,kind,properties):
  self.ids+=1;k=str(self.ids);self.resources.append(f'[sub_resource type="{kind}" id="{k}"]\n{properties}\n');return k
 def mat(self,color,glow=False):
  key=(color,glow)
  if key not in self.materials:
   c=tuple(int(color[i:i+2],16)/255 for i in (0,2,4));s=', '.join(map(str,c))
   self.materials[key]=self.res('StandardMaterial3D',f'albedo_color = Color({s}, 1)\nroughness = 0.88\n'+(f'emission_enabled = true\nemission = Color({s}, 1)\nemission_energy_multiplier = 1.5\n' if glow else ''))
  return self.materials[key]
 def node(self,name,kind,parent,pos=(0,0,0),extra=''):
  self.nodes.append(f'[node name="{name}" type="{kind}" parent="{parent}"]\nposition = Vector3{tuple(pos)}\n{extra}\n'.replace('Vector3(', 'Vector3('))
 def shape(self,name,kind,size,pos,color,parent='Model',rotation=None,glow=False):
  mat=self.mat(color,glow)
  if kind=='BoxMesh': props=f'size = Vector3{tuple(size)}'
  elif kind=='CylinderMesh':props=f'top_radius = {size[0]}\nbottom_radius = {size[1]}\nheight = {size[2]}\nradial_segments = 7\nrings = 1'
  elif kind=='SphereMesh':props=f'radius = {size[0]}\nheight = {size[1]}\nradial_segments = 8\nrings = 4'
  mesh=self.res(kind,props+f'\nmaterial = SubResource("{mat}")')
  extra=f'mesh = SubResource("{mesh}")'
  if rotation:extra+=f'\nrotation = Vector3{tuple(rotation)}'
  self.node(name,'MeshInstance3D',parent,pos,extra)
 def box(self,n,s,p,c,**kw): self.shape(n,'BoxMesh',s,p,c,**kw)
 def cone(self,n,s,p,c,**kw): self.shape(n,'CylinderMesh',s,p,c,**kw)
 def ball(self,n,s,p,c,**kw): self.shape(n,'SphereMesh',s,p,c,**kw)
 def save(self):
  ext='[ext_resource type="Script" path="res://scripts/pawn.gd" id="pawn"]\n' if self.pawn else ''
  script='script = ExtResource("pawn")\n' if self.pawn else ''
  data=f'[gd_scene load_steps={self.ids+1+int(self.pawn)} format=3]\n\n'+ext+'\n'+'\n'.join(self.resources)+f'\n[node name="{self.name}" type="Node3D"]\n'+script+'\n'+'\n'.join(self.nodes)
  (ROOT/(self.name+'.tscn')).write_text(data)

s=Scene('survivor',True)
s.box('Torso',(.68,.7,.36),(0,1.35,0),'b3aa76')
s.box('Vest',(.58,.5,.13),(0,1.4,.23),'62654c')
s.box('Belt',(.72,.12,.39),(0,.99,0),'544532')
s.box('Backpack',(.45,.52,.24),(0,1.35,-.28),'354d3d')
s.ball('Head',(.25,.49),(0,1.99,0),'c7956e')
s.cone('Hat',(.3,.35,.17),(0,2.2,0),'70744e')
s.cone('Brim',(.44,.44,.055),(0,2.13,.04),'777b55')
for side,k in [('L',-1),('R',1)]:
 s.node('Leg'+side,'Node3D','Model',(k*.2,.95,0))
 s.box('Trouser',(.25,.62,.28),(0,-.31,0),'455647',parent='Model/Leg'+side)
 s.box('Boot',(.28,.23,.48),(0,-.72,.10),'343832',parent='Model/Leg'+side)
 s.node('Arm'+side,'Node3D','Model',(k*.43,1.65,0))
 s.box('Sleeve',(.23,.33,.25),(0,-.12,0),'b3aa76',parent='Model/Arm'+side)
 s.box('Forearm',(.17,.34,.19),(0,-.39,.06),'c7956e',parent='Model/Arm'+side)
s.box('Rifle',(.12,.15,.87),(0,-.45,.45),'343c38',parent='Model/ArmR')
s.save()
s=Scene('raptor',True)
s.ball('Torso',(.68,1.1),(0,1.27,-.05),'63724a')
s.box('Chest',(.63,.61,.85),(0,1.49,.35),'718354')
s.box('Neck',(.43,.73,.40),(0,1.98,.49),'7d8c59',rotation=(.45,0,0))
s.box('Skull',(.52,.46,.92),(0,2.23,.98),'7a8756')
s.box('Jaw',(.47,.13,.79),(0,1.97,1.01),'b3b185')
s.box('Nose',(.47,.20,.22),(0,2.13,1.5),'67774e')
for k in [-1,1]:
 s.ball('Eye'+str(k),(.068,.13),(k*.265,2.30,1.10),'e8c858',glow=True)
 s.box('Pupil'+str(k),(.017,.085,.04),(k*.323,2.30,1.12),'101d18')
 for j in range(4):s.cone('Tooth'+str(k)+str(j),(.045,0,.15),(k*.22,1.99,.84+j*.16),'e6ddbb')
s.node('Tail','Node3D','Model',(0,1.18,-.40))
s.cone('TailBase',(.15,.35,1.35),(0,-.12,-.60),'68794d',parent='Model/Tail',rotation=(math.pi/2,0,0))
s.cone('TailTip',(0,.17,1.4),(0,.0,-1.85),'617049',parent='Model/Tail',rotation=(-math.pi/2,0,0))
for side,k in [('L',-1),('R',1)]:
 s.node('Leg'+side,'Node3D','Model',(k*.46,1.22,-.1))
 s.box('Thigh',(.34,.54,.41),(0,-.20,0),'53633f',parent='Model/Leg'+side,rotation=(.4,0,0))
 s.box('Shin',(.17,.54,.21),(0,-.66,.07),'707951',parent='Model/Leg'+side,rotation=(-.4,0,0))
 s.box('Foot',(.29,.16,.62),(0,-1.0,.30),'a6a782',parent='Model/Leg'+side)
 s.node('Arm'+side,'Node3D','Model',(k*.39,1.7,.49))
 s.box('ClawArm',(.14,.34,.2),(0,-.16,.10),'627747',parent='Model/Arm'+side,rotation=(.65,0,0))
 s.box('Claw',(.18,.09,.27),(0,-.3,.23),'d6cbae',parent='Model/Arm'+side)
for j in range(6): s.cone('Spine'+str(j),(0,.16,.32),(0,1.74,-.5+j*.17),'425435')
s.save()
s=Scene('tree')
s.cone('Trunk',(.13,.24,2.9),(0,1.45,0),'69523c')
for i,(r,y) in enumerate([(1.45,2.3),(1.2,3.0),(.90,3.65)]):
 s.cone('Crown'+str(i),(0,r,2.2),(0,y,0),['345842','416a4c','527451'][i])
s.save()
s=Scene('rock')
s.ball('Stone',(1.05,1.6),(0,.45,0),'7d8478')
s.ball('StoneSmall',(.68,.8),(.70,.12,.28),'687567')
s.save()
s=Scene('tent')
s.box('Platform',(1.82,.16,1.85),(0,.08,0),'76654c')
s.cone('CanvasRoof',(0,1.22,1.55),(0,1.02,0),'c6b481')
s.box('Door',(.55,.73,.1),(0,.55,.81),'343d31')
s.box('DoorLintel',(.67,.12,.13),(0,.96,.82),'d4c698')
s.save()
s=Scene('fire')
for i in range(7):
 a=i*math.tau/7;s.ball('Stone'+str(i),(.23,.31),(math.sin(a)*.65,.15,math.cos(a)*.65),'727a6a')
s.box('LogA',(.19,.15,1.0),(0,.23,0),'795034')
s.box('LogB',(1,.15,.19),(0,.28,0),'68482e')
s.cone('Flame',(0,.4,1.15),(0,.73,0),'edaa42',glow=True)
s.cone('FlameCore',(0,.23,.7),(0,.53,.2),'ffdf85',glow=True)
s.node('FireLight','OmniLight3D','.',(0,1.5,0),'light_color = Color(1, 0.66, 0.3, 1)\nlight_energy = 2.0\nomni_range = 9.0')
s.save()
s=Scene('generator')
s.box('Foundation',(1.82,.2,1.82),(0,.1,0),'788075')
s.box('Housing',(1.4,.9,1.12),(0,.65,0),'596c64')
s.box('CopperPanel',(1.43,.23,1.15),(0,.85,0),'b79757')
for k in [-1,1]:s.cone('Turbine'+str(k),(.25,.25,.62),(k*.40,1.2,0),'a9b3a2')
s.cone('Mast',(.06,.06,2.4),(.65,1.4,-.65),'555d54')
s.ball('Indicator',(.12,.24),(.65,2.65,-.65),'9bcdd0',glow=True)
s.save()
s=Scene('shelter')
for x in [-.85,.85]:
 s.box('Post'+str(x),(.17,1.6,.23),(x,.8,0),'697764')
 s.ball('Insulator'+str(x),(.14,.23),(x,1.6,0),'9abbb0')
for y in [.45,.85,1.25]:s.box('Wire'+str(y),(1.7,.045,.035),(0,y,0),'acb19a')
s.box('DangerSign',(.35,.4,.07),(0,1.05,.02),'d3b45c')
s.save()
s=Scene('tower')
s.box('Base',(1.65,.23,1.65),(0,.12,0),'858c79')
for x in [-.53,.53]:
 for z in [-.53,.53]:s.box('Leg'+str(x)+str(z),(.14,1.6,.14),(x,.92,z),'626e59')
s.box('Deck',(1.60,.18,1.60),(0,1.73,0),'b2aa7a')
s.node('Gun','Node3D','Model',(0,1.9,0))
s.box('CrossbowStock',(.17,.2,1.15),(0,.15,.3),'705837',parent='Model/Gun')
s.box('Bow', (1.2,.13,.13),(0,.2,.58),'9d8452',parent='Model/Gun')
s.box('Bolt',(.04,.04,1.6),(0,.3,.65),'ddd0a6',parent='Model/Gun')
s.save()
s=Scene('lab')
s.box('Base',(1.86,.25,1.86),(0,.13,0),'8c9786')
s.box('Room',(1.70,1.4,1.65),(0,.95,0),'b5baa4')
s.box('Roof',(1.88,.20,1.84),(0,1.76,0),'486e63')
s.box('Door',(.5,.9,.07),(0,.65,.85),'3e5750')
for x in [-.55,.55]:s.box('Window'+str(x),(.37,.44,.09),(x,1.12,.86),'8fae9f')
s.cone('Dish',(.50,.12,.24),(.35,2.2,0),'d3d1b4',rotation=(.3,0,.3))
s.save()
s=Scene('fossil')
s.ball('Mound',(1.3,.35),(0,.1,0),'706349')
for i in range(5):s.cone('Rib'+str(i),(.1,.1,1.15),(-.50+i*.27,.30,0),'c6b997',rotation=(math.pi/2,0,.25))
s.ball('Skull',(.33,.45),(.8,.35,.1),'e1ceaa')
s.save()
print(f'Generated {len(list(ROOT.glob("*.tscn")))} editable model scenes')
