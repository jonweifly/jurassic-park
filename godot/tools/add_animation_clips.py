"""Install editable animation libraries on the original primitive character scenes."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def track(path, times, values, n):
    return f'''tracks/{n}/type = "value"
tracks/{n}/imported = false
tracks/{n}/enabled = true
tracks/{n}/path = NodePath("{path}")
tracks/{n}/interp = 1
tracks/{n}/loop_wrap = true
tracks/{n}/keys = {{"times": PackedFloat32Array({', '.join(map(str,times))}), "transitions": PackedFloat32Array({', '.join('1' for _ in times)}), "update": 0, "values": [{', '.join(values)}]}}
'''

def vec(x=0,y=0,z=0): return f'Vector3({x}, {y}, {z})'
for name in ('survivor','raptor'):
    clips = []
    states = [('idle',1.6,True),('walk',0.55,True),('attack',0.4,False),('death',0.8,False)]
    if name == 'survivor': states += [('chop',1.35,False),('mine',1.35,False),('build',0.9,True),('carry',0.65,True),('carry_idle',1.6,True)]
    for state,length,loop in states:
        clip = f'[sub_resource type="Animation" id="{state}"]\nresource_name = "{state}"\nlength = {length}\nloop_mode = {int(loop)}\n'
        n=0
        for part,sign in [('LegL',1),('LegR',-1),('ArmL',-1),('ArmR',1)]:
            vals=[vec()]*3
            if state in ('walk','carry'): vals=[vec(-0.38*sign),vec(0.38*sign),vec(-0.38*sign)]
            if state in ('carry','carry_idle') and part.startswith('Arm'): vals=[vec(-0.85,0,0.15*sign)]*3
            if state=='attack' and part=='ArmR': vals=[vec(),vec(-1.1),vec()]
            clip+=track(f'Model/{part}:rotation',[0,length/2,length],vals,n);n+=1
            if state in ('chop','mine','build') and part.startswith('Arm'):
                # Replace this arm track with a wind-up, strike and recovery.
                begin=clip.index(f'tracks/{n-1}/type')
                contact=0.65 if state=='build' else 1.1
                rotations=[vec(-0.25),vec(-2.2,0,0.12*sign),vec(0.3,0,0.1*sign),vec(-0.25)] if part=='ArmR' else [vec(-0.3,0,-0.15)]*4
                clip=clip[:begin]+track(f'Model/{part}:rotation',[0,contact-0.22,contact,length],rotations,n-1)
        vals=[vec(),vec(0,0.025 if state=='idle' else 0.045,0),vec()]
        if state=='death': vals=[vec(),vec(0,-0.15,0),vec(0,-0.35,0)]
        clip+=track('Model:position',[0,length/2,length],vals,n);n+=1
        # Keep yaw free for navigation; animate pitch and roll independently.
        clip+=track('Model:rotation:x',[0,length/2,length],['0','-0.3' if state=='attack' else ('0.12' if state in ('chop','mine','build') else '0'),'0'],n);n+=1
        clip+=track('Model:rotation:z',[0,length],['0','1.45' if state=='death' else '0'],n);n+=1
        if name=='raptor':clip+=track('Model/Tail:rotation:y',[0,length/2,length],['-0.1','0.1','-0.1'],n)
        clips.append(clip)
    resource=f'[gd_resource type="AnimationLibrary" load_steps={len(states)+1} format=3]\n\n'+'\n'.join(clips)+'\n[resource]\n_data = {'+', '.join(f'"{state}": SubResource("{state}")' for state,_,_ in states)+'}\n'
    (ROOT/'scenes/models'/f'{name}_animations.tres').write_text(resource)
    p=ROOT/'scenes/models'/f'{name}.tscn'
    text=p.read_text()
    if 'AnimationPlayer' not in text:
        import re
        text=re.sub(r'load_steps=(\d+)',lambda m:f'load_steps={int(m[1])+1}',text,count=1)
        at=text.index('\n')
        text=text[:at]+f'\n[ext_resource type="AnimationLibrary" path="res://scenes/models/{name}_animations.tres" id="motions"]\n'+text[at:]
        text+='\n[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\ncallback_mode_process = 2\nlibraries = {&"": ExtResource("motions")}\n'
    if '[node name="Visual"' not in text:
        import re
        text=re.sub(r'load_steps=(\d+)',lambda m:f'load_steps={int(m[1])+1}',text,count=1)
        at=text.index('\n')
        text=text[:at]+'\n[ext_resource type="Script" path="res://scripts/pawn_visual.gd" id="visual"]\n'+text[at:]
        text+='\n[node name="Visual" type="Node" parent="."]\nscript = ExtResource("visual")\n'
        if name=='survivor': text+='work_equipment = true\n'
    p.write_text(text)
print('Installed editable idle, walk, attack and death animation clips.')
