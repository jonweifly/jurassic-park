"""Generate thin Godot wrappers; never rewrite gameplay data or the baked island."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; scenes=ROOT/'godot/scenes/models'
for name in ['survivor','raptor','trex']:
 human=name=='survivor'
 text=f'''[gd_scene load_steps={11 if human else 4} format=3]
[ext_resource type="Script" path="res://scripts/pawn.gd" id="pawn"]
[ext_resource type="Script" path="res://scripts/pawn_visual.gd" id="visual"]
[ext_resource type="PackedScene" path="res://assets/models/{name}.glb" id="model"]
'''
 if human:
  for tool in ['axe','pickaxe','hammer','wood_cargo','ore_cargo','rifle']:
   text+=f'[ext_resource type="PackedScene" path="res://assets/models/{tool}.glb" id="{tool}"]\n'
 text+=f'\n[node name="{name}" type="Node3D"]\nscript = ExtResource("pawn")\n\n[node name="Model" parent="." instance=ExtResource("model")]\n'
 # Bone rest basis of hands points down. Compensate grip basis without changing authored animation.
 if human:
  text+='''
[node name="RightHandGrip" type="BoneAttachment3D" parent="Model/Rig/Skeleton3D"]
bone_name = "handR"
bone_idx = 9
[node name="Grip" type="Node3D" parent="Model/Rig/Skeleton3D/RightHandGrip"]
rotation = Vector3(3.32694, 0, 0)
[node name="Rifle" parent="Model/Rig/Skeleton3D/RightHandGrip/Grip" instance=ExtResource("rifle")]
[node name="CarryGrip" type="BoneAttachment3D" parent="Model/Rig/Skeleton3D"]
bone_name = "spine"
bone_idx = 1
[node name="Cargo" type="Node3D" parent="Model/Rig/Skeleton3D/CarryGrip"]
position = Vector3(0, 0.08, 0.38)
'''
 text+='''
[node name="Visual" type="Node" parent="."]
script = ExtResource("visual")
animator_path = NodePath("../Model/AnimationPlayer")
'''
 if human:
  text+='''work_equipment = true
contact_rig_path = NodePath("../Model/Rig/Skeleton3D")
hand_socket_path = NodePath("../Model/Rig/Skeleton3D/RightHandGrip/Grip")
cargo_socket_path = NodePath("../Model/Rig/Skeleton3D/CarryGrip/Cargo")
rifle_path = NodePath("../Model/Rig/Skeleton3D/RightHandGrip/Grip/Rifle")
tool_grip = Vector3(0, 0, 0)
cargo_origin = Vector3(0, 0, 0)
'''
  for tool in ['axe','pickaxe','hammer','wood_cargo','ore_cargo']: text+=f'{tool}_scene = ExtResource("{tool}")\n'
 if not human: text+='locomotion_stride = 1.72\n'
 text+='\n[editable path="Model"]\n'
 (scenes/(name+'.tscn')).write_text(text)
for name in ['broadleaf','tree','snow_tree','rock','fern','tent','fire','generator','shelter','gate','tower','lab','fossil']:
 s=f'''[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://assets/models/{name}.glb" id="model"]
[node name="{name}" type="Node3D"]
[node name="Model" parent="." instance=ExtResource("model")]
'''
 if name=='fire': s+='''
[node name="FireLight" type="OmniLight3D" parent="."]
position = Vector3(0, 1.2, 0)
light_color = Color(1, 0.61, 0.28, 1)
light_energy = 1.5
omni_range = 9.0
'''
 (scenes/(name+'.tscn')).write_text(s)
