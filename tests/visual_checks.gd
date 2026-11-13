extends SceneTree
## Run with a graphical renderer. Captures the actual viewport and checks the vision mask.

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level: Node2D = load("res://scenes/levels/first_crossing.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://docs/previews")
	root.get_texture().get_image().save_png("res://docs/previews/start.png")
	level.hud.overlay.hide()
	level._on_sound_emitted(level.eye.global_position, 1.0)
	for wave in level.waves.get_children():
		wave.age = 0.45
		wave.set_process(false)
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://docs/previews/gameplay.png")
	var transform: Transform2D = root.get_canvas_transform()
	_check_pixel(image, transform * Vector2(240, 448), true, "Sound reflection reveals nearby wall edge")
	_check_pixel(image, transform * Vector2(240, 540), false, "Wall interiors remain black even beside locator")
	_check_pixel(image, transform * Vector2(600, 448), false, "Edges stay black until wave reaches them")
	_check_pixel(image, transform * Vector2(160, 426), false, "Player body stays invisible")
	# A second preview shows the ferry's reflected outline mid-crossing.
	for wave in level.waves.get_children():
		wave.queue_free()
	await process_frame
	level.ferry.position = Vector2(960, 448)
	level.player.reset_to(Vector2(1088, 426))
	level.eye.reset_to(Vector2(1088, 512), level.ferry)
	level._update_camera(0.0, true)
	level._on_sound_emitted(level.eye.global_position, 1.0)
	for wave in level.waves.get_children():
		wave.age = 0.55
		wave.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/crossing.png")
	level._reset_world()
	level.debug_view = true
	level.vision.set_shader_parameter("debug_visible", true)
	level.player.debug_visible = true
	level.player.queue_redraw()
	level.get_node("DebugRoute").show()
	await process_frame
	await RenderingServer.frame_post_draw
	var debug_image: Image = root.get_texture().get_image()
	debug_image.save_png("res://docs/previews/debug.png")
	_check_pixel(debug_image, transform * Vector2(600, 480), true, "Debug view reveals terrain for level editing")
	print("Visual checks: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)

func _check_pixel(image: Image, point: Vector2, should_be_light: bool, description: String) -> void:
	var pixel := image.get_pixelv(Vector2i(point))
	var is_light := pixel.r > 0.25
	if is_light == should_be_light:
		print("PASS  ", description)
	else:
		failures += 1
		push_error("FAIL  " + description + " pixel=" + str(pixel))
