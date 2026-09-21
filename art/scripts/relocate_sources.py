"""Keep the editable Blender source portable with project-relative texture paths."""
import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[2]
bpy.context.preferences.filepaths.save_version=0
for file in sorted((root/'art/source').glob('*.blend')):
 bpy.ops.wm.open_mainfile(filepath=str(file))
 for image in bpy.data.images:
  if image.name.startswith('expedition_'): image.filepath='//../textures/'+image.name+'.png'
 bpy.ops.wm.save_as_mainfile(filepath=str(file),compress=True)
print('PORTABLE BLENDER SOURCES COMPLETE')
