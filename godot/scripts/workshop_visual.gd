extends Node3D
const Visual = preload("res://scripts/pawn_visual.gd")

func _ready() -> void:
	var model: Node3D = $Model
	# Reuse the camp shell, with a distinct open workbench, drawers and equipment rack.
	Visual.box(model, Vector3(1.5,.14,.55), Vector3(0,.86,1.04), Color("927247"))
	for x in [-.62,.62]:
		Visual.box(model, Vector3(.10,.78,.12), Vector3(x,.4,1.02), Color("465149"))
	Visual.box(model, Vector3(.52,.45,.42), Vector3(-.38,.54,1.0), Color("526855"))
	for y in [.43,.6,.76]: Visual.box(model, Vector3(.16,.025,.035), Vector3(-.38,y,1.23), Color("c3b783"))
	Visual.box(model, Vector3(.32,.16,.22), Vector3(.40,1.0,1.03), Color("52635d"))
	Visual.box(model, Vector3(.075,.20,.05), Vector3(.40,1.1,1.15), Color("d9d5ad"))
	Visual.box(model, Vector3(.19,.05,.05), Vector3(.40,1.1,1.16), Color("d9d5ad"))
	Visual.box(model, Vector3(1.28,.58,.075), Vector3(0,1.38,.83), Color("384f44"))
	for x in [-.48,-.22,.06]:
		Visual.box(model, Vector3(.045,.36,.07), Vector3(x,1.4,.89), Color("adb8a7"))
		Visual.box(model, Vector3(.13,.07,.08), Vector3(x,1.56,.89), Color("747e73"))
	Visual.box(model, Vector3(.3,.08,.07), Vector3(.4,1.46,.92), Color("b2a171"))
	var sign := Label3D.new()
	sign.text = "装备工坊"
	sign.position = Vector3(0,2.15,1.02)
	sign.font_size = 45
	sign.pixel_size = .008
	sign.modulate = Color("ead09a")
	model.add_child(sign)
