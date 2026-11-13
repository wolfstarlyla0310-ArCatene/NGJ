class_name WaveFactory
extends RefCounted
## Configure before entering the tree: _ready may snap the pulse or calculate its force.

static func spawn(parent: Node2D, origin: Vector2, type: WaveTypes.WaveType = WaveTypes.WaveType.WHITE, options: Dictionary = {}) -> Node2D:
	var wave := Node2D.new()
	wave.set_script(preload("res://scripts/sound_wave.gd") if options.get("echo", false) else preload("res://scripts/force_pulse.gd"))
	wave.wave_type = type
	for key in options:
		if key != "echo":
			wave.set(key, options[key])
	wave.position = parent.to_local(origin)
	parent.add_child(wave)
	return wave
