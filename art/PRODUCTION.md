# Asset production checkpoint

User authorization: complete remaining art stages continuously, with independent 3D models,
skin/rig/animation, full environment replacement, native runtime screenshots and gameplay
regressions. No phase approvals. Do not stop on unavailable external image/3D generation.

Art direction: grounded stylized jungle expedition; natural silhouettes, matte worn canvas,
oxidized green machinery, warm timber and cool undergrowth. Keep current Godot 4.4.1 GL
Compatibility runtime and verified economy/AI. Models use metres and Godot +Z forward.

Pipeline: local Blender 4.5 LTS -> editable .blend -> uncompressed glTF 2 GLB -> native Godot
imports with generated LODs. Shared authored PBR atlas. Original procedural mesh authoring,
no Warcraft meshes or externally licensed assets. Source scripts and asset manifest retained.

Stages (continue through all):
- [x] Independent survivor mesh, skeleton, weighted joints, work/carry/combat/death clips.
- [x] Raptor anatomy, weighted spine/tail/jaw/limbs and locomotion/attack/death clips.
- [x] Branched broadleaf tree with shaped foliage; sewn canvas tent with internal frame.
- [x] Distinct tyrannosaur family, conifer and rainforest variants, rocks/ferns/ground cover.
- [x] Campfire, generator, fence/gate, bow tower, base/lab, fossil excavator, props/tools.
- [x] Replace runtime assets, retain building interactions and forest batching; terrain/PBR/light.
- [x] Native screenshots/animation verification, complete gameplay regressions and performance.
- [x] Delivery report, previews, source/asset inventory and honest remaining limitations.

Initial tool check: Blender absent. Public Blender mirrors available; install only under .tools.
Use web-3d-asset-pipeline skill for shipping discipline. Do not overwrite the baked map layout.

Delivery: docs/art/production-delivery.md. 25 GLBs and 25 portable Blender sources,
shared 1K albedo/roughness/normal atlas; 16-bone survivor and two 20-bone dinosaurs.
279 checks + 7 encounter scenarios pass. 25 Khronos validations: zero errors,
three known NODE_SKINNED_MESH_NON_ROOT warnings verified in native Godot.
Flat-ground foot support is solved offline; live slope IK, facial rigs, cloth
simulation, hand-sculpted finish and low-end/80-minute soak testing remain limitations.

## V0.6 expedition props

Five additional original static props are isolated under `source/expedition` and
`godot/assets/expedition`: a formed parabolic relay dish, medical case, weather
mast, archive cabinet and egg nest. Editable Blender parts are retained before
joining each runtime mesh. 11,644 triangles total, approximately 371 KiB;
structural and Khronos checks both pass, with no errors or warnings.
See `expedition-model-manifest.json`, `expedition-validation.json`,
`expedition-validation-khronos.json` and `docs/development/content-delivery.md`.
These five resources are additional to the original 25 GLBs, not replacements
for the independently rigged characters or original tree LODs.
