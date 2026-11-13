extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://docs/previews")
	root.get_texture().get_image().save_png("res://docs/previews/wave-jump-start.png")
	level.restart_run()
	level.eye.input_enabled = false
	for _i in range(12):
		await physics_frame
	level.fire_pulse()
	for _i in range(25):
		await physics_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	picture.save_png("res://docs/previews/wave-jump.png")
	var transform := root.get_canvas_transform()
	var body := picture.get_pixelv(Vector2i(transform * level.player.global_position))
	var floor_pixel := picture.get_pixelv(Vector2i(transform * Vector2(420, 570)))
	var passed: bool = body.r > 0.5 and floor_pixel.r > 0.5 and level.player.position.y < 490.0
	print("PASS" if passed else "FAIL", "  Real rendered wave jump shows airborne body and permanently visible terrain")
	level._set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(0 if passed else 1)
