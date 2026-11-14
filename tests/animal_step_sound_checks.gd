extends SceneTree
## 独立物理场景：不改主地图，覆盖爬阶动作、守边和动物叫声按钮链路。

var world: Node2D
var fields: Node2D
var failures: Array[String] = []
var button_cases_run := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value:
		print("PASS  ", message)
	else:
		failures.append(message)
		push_error("FAIL  " + message)

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func fresh_world() -> TileMapLayer:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	fields = Node2D.new()
	fields.add_to_group("sound_fields")
	world.add_child(fields)
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://resources/whitebox_tileset.tres")
	world.add_child(terrain)
	if "--captures" in OS.get_cmdline_user_args():
		var camera := Camera2D.new()
		camera.position = Vector2(64, 104)
		camera.zoom = Vector2(5, 5)
		world.add_child(camera)
	return terrain

func save_capture(filename: String) -> void:
	if "--captures" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/" + filename + ".png")

func animal_at(pos: Vector2) -> Animal:
	var animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	animal.position = pos
	world.add_child(animal)
	return animal

func blue_at(pos: Vector2, side: float = 512.0) -> SoundField:
	var field := SoundField.new()
	field.level = 1
	field.color = SoundField.color_for_level(1)
	field.side_length = side
	field.lifetime = 30.0
	field.position = pos
	fields.add_child(field)
	return field

func floor_tiles(terrain: TileMapLayer, dir: int, height: int = 1, ceiling: bool = false) -> void:
	for x in range(-8, 8):
		terrain.set_cell(Vector2i(x if dir > 0 else -x - 1, 8), 0, Vector2i.ZERO)
	for x in range(4, 8):
		for y in range(8 - height, 8):
			terrain.set_cell(Vector2i(x if dir > 0 else -x - 1, y), 0, Vector2i.ZERO)
	if ceiling:
		for x in range(-8, 8):
			terrain.set_cell(Vector2i(x, 6), 0, Vector2i.ZERO)

func _run() -> void:
	if "--visual" in OS.get_cmdline_user_args():
		await _visual_demo()
		return
	await _walk_step(1)
	await _walk_step(-1)
	await _five_cells(1, false)
	await _five_cells(-1, true)
	await _narrow_stairs()
	await _blocked_step(2, false)
	await _blocked_step(1, true)
	await _interruptions()
	await _buttons(false)
	await _buttons(true)
	check(button_cases_run == 2, "Both button integration scenarios completed")
	world.queue_free()
	await frames(3)
	print("\nAnimal step/sound checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _walk_step(dir: int) -> void:
	var terrain := await fresh_world()
	floor_tiles(terrain, dir)
	# 上层台面和天花板之间只留一格：复现房间 6 的实际通道净空。
	for x in range(-8, 8):
		terrain.set_cell(Vector2i(x, 5), 0, Vector2i.ZERO)
	var animal := animal_at(Vector2(40 * dir, 120))
	await frames(8)
	blue_at(Vector2(-8 * dir, 120))
	var sprite: Sprite2D = animal.get_node("Sprite2D")
	var turned := false
	var rose_slowly := false
	var max_motion := 0.0
	var captured := false
	var before := animal.position
	for _i in 260:
		await physics_frame
		max_motion = maxf(max_motion, animal.position.distance_to(before))
		if absf(sprite.rotation + dir * PI * 0.5) < 0.01:
			turned = true
			if animal.position.y < before.y - 0.01 and animal.position.y > 104.0:
				rose_slowly = true
				if not captured and animal.position.y < 112.0 and dir > 0:
					captured = true
					save_capture.call_deferred("animal_step_climbing")
		before = animal.position
	check(turned and rose_slowly, "Facing %d: turns 90 degrees and crawls up the side" % dir)
	check(max_motion < 2.0, "Facing %d: climb moves continuously without teleporting" % dir)
	check(animal.position.x * dir > 96.0 and animal.position.y < 105.0,
		"Facing %d: reaches the upper platform and continues forward" % dir)
	check(is_zero_approx(sprite.rotation), "Facing %d: faces forward again on top" % dir)
	check(animal.is_on_floor() and animal.position.x * dir < 120.0,
		"Facing %d: stays on the upper platform at its edge" % dir)
	var edge := animal.position
	await frames(90)
	check(animal.position.distance_to(edge) < 0.1, "Facing %d: sustained blue field cannot push it off the edge" % dir)
	var called_at_edge := false
	for child in fields.get_children():
		if child is SoundField and child.emitter == animal:
			called_at_edge = true
	check(called_at_edge, "Facing %d: still calls while stopped at the edge" % dir)

func _blocked_step(height: int, ceiling: bool) -> void:
	var terrain := await fresh_world()
	floor_tiles(terrain, 1, height, ceiling)
	var animal := animal_at(Vector2(40, 120))
	await frames(8)
	blue_at(Vector2(-8, 120))
	var highest := animal.position.y
	var attempts := 0
	var was_climbing := false
	var captured := false
	for _i in 200:
		await physics_frame
		highest = minf(highest, animal.position.y)
		var climbing := animal._climb_phase != Animal.ClimbPhase.NONE
		if climbing and not was_climbing:
			attempts += 1
		was_climbing = climbing
		if height > 1 and animal.position.y < 104.0 and not captured:
			captured = true
			save_capture.call_deferred("animal_tall_wall_peak")
	if height > 1:
		check(highest < 104.0 and highest > 102.0 and attempts == 1,
			"Tall wall: crawls up one tile once, then releases instead of climbing higher or retrying")
	check(animal.position.x < 57.0 and animal.position.y > 119.0 and animal.is_on_floor(),
		"Low ceiling prevents climbing" if ceiling else "Tall wall: falls back down and lands on the original floor")
	check(is_zero_approx((animal.get_node("Sprite2D") as Sprite2D).rotation), "Blocked animal keeps its normal orientation")

func _five_cells(dir: int, persistent: bool) -> void:
	var terrain := await fresh_world()
	for x in range(-40, 40):
		terrain.set_cell(Vector2i(x, 8), 0, Vector2i.ZERO)
	check(terrain.tile_set.tile_size == Vector2i(16, 16), "Distance uses the actual outer terrain tile grid")
	var animal := animal_at(Vector2(0, 120))
	await frames(8)
	var blue := blue_at(Vector2(-32 * dir, 120))
	if not persistent:
		blue.lifetime = 0.025
	await frames(20)
	check(absf(animal.velocity.x) > 1.0, "Animal keeps walking after a short triggering blue field expires")
	await frames(160)
	check(absf(animal.position.x - 80.0 * dir) < 0.05 and animal.is_on_floor(),
		"Facing %d: one blue trigger travels exactly five terrain tiles (80 px)" % dir)
	var stopped := animal.position
	await frames(50)
	check(animal.position.distance_to(stopped) < 0.01 and is_zero_approx(animal.velocity.x),
		"Same blue field cannot extend the command or restart it after five tiles")
	blue_at(animal.position - Vector2(32 * dir, 0))
	await frames(140)
	check(absf(animal.position.x - 160.0 * dir) < 0.05,
		"A new blue field starts another five-tile command")

func _narrow_stairs() -> void:
	var terrain := await fresh_world()
	floor_tiles(terrain, 1)
	for x in range(5, 8):
		for y in range(11 - x, 7):
			terrain.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	var animal := animal_at(Vector2(40, 120))
	await frames(8)
	blue_at(Vector2(-8, 120))
	await frames(470)
	check(animal.position.x > 112.0 and animal.position.y < 57.0 and animal.is_on_floor(),
		"Crawls up consecutive one-tile-wide steps and stops on the top step")

func _interruptions() -> void:
	var terrain := await fresh_world()
	floor_tiles(terrain, 1)
	var animal := animal_at(Vector2(40, 120))
	await frames(8)
	var blue := blue_at(Vector2(-8, 120))
	for _i in 100:
		await physics_frame
		if animal._climb_phase == Animal.ClimbPhase.RISE:
			break
	blue.queue_free()
	await frames(110)
	check(animal.position.x > 64.0 and animal.is_on_floor() and animal._climb_phase == Animal.ClimbPhase.NONE,
		"Finishes the current climb safely when the triggering blue field expires")
	animal.reset_home()
	await frames(8)
	blue_at(Vector2(-8, 120))
	for _i in 100:
		await physics_frame
		if animal._climb_phase == Animal.ClimbPhase.RISE:
			break
	animal.reset_home()
	check(animal.position.distance_to(animal._home_position) < 0.01 and animal._climb_phase == Animal.ClimbPhase.NONE
		and is_zero_approx((animal.get_node("Sprite2D") as Sprite2D).rotation), "Reset during climbing restores position and orientation")
	await frames(8)
	for _i in 100:
		await physics_frame
		if animal._climb_phase == Animal.ClimbPhase.RISE:
			break
	var yellow := blue_at(animal.position, 32.0)
	yellow.level = 2
	await frames(3)
	check(animal._climb_phase == Animal.ClimbPhase.NONE and animal._knockback_remaining > 0.0
		and is_zero_approx((animal.get_node("Sprite2D") as Sprite2D).rotation), "Yellow knockback interrupts climbing cleanly")

func _buttons(moving: bool) -> void:
	var terrain := await fresh_world()
	for x in range(-8, 16):
		terrain.set_cell(Vector2i(x, 8), 0, Vector2i.ZERO)
	var animal := animal_at(Vector2(40 if moving else 0, 120))
	animal.idle_wave_interval = 100.0 if moving else 0.1
	animal.wave_lifetime = 0.15
	var buttons := Node2D.new()
	world.add_child(buttons)
	var rebound: DoorButton = load("res://scenes/world/button_rebound.tscn").instantiate()
	var once: DoorButton = load("res://scenes/world/button_once.tscn").instantiate()
	for button in [rebound, once]:
		button.position = Vector2(80 if moving else 32, 120)
		button.door_cells.assign([Vector2i(20, 7)])
		buttons.add_child(button)
	var door_tiles := TileMapLayer.new()
	door_tiles.tile_set = load("res://resources/door_tileset.tres")
	door_tiles.set_cell(Vector2i(20, 7), 0, Vector2i(3, 2))
	world.add_child(door_tiles)
	var manager := PuzzleDoorManager.new()
	manager.doors_layer = door_tiles
	manager.buttons_root = buttons
	manager.log_doors = false
	world.add_child(manager)
	# 先只接回弹按钮，避免双按钮同时满足时整组锁死。
	once.door_cells.clear()
	manager.setup([])
	await frames(4)
	var player_wave := SoundField.new()
	player_wave.side_length = 16.0
	player_wave.position = rebound.position
	fields.add_child(player_wave)
	await frames(2)
	check(not rebound.is_pressed(), "Ordinary lv0 wave still cannot press a button")
	player_wave.queue_free()
	if moving:
		blue_at(Vector2(16, 120), 32.0)
	var pressed := false
	for _i in 70:
		await physics_frame
		if rebound.is_pressed() and once.is_pressed() and manager.is_door_open(0):
			pressed = true
			break
	check(pressed, "%s animal's actual call presses both button types and opens the linked door" % ("Moving" if moving else "Idle"))
	check(animal.position.distance_to(rebound.position) > 16.0, "Sound triggers the button without body contact")
	animal.set_physics_process(false)
	await frames(30)
	check(not rebound.is_pressed() and not manager.is_door_open(0), "Rebound button releases and closes its door when the call ends")
	check(once.is_latched(), "One-shot button remains latched after the call ends")
	button_cases_run += 1

func _visual_demo() -> void:
	var terrain := await fresh_world()
	floor_tiles(terrain, 1)
	var animal := animal_at(Vector2(40, 120))
	var button: DoorButton = load("res://scenes/world/button_once.tscn").instantiate()
	button.position = Vector2(144, 104)
	world.add_child(button)
	var camera := Camera2D.new()
	camera.position = Vector2(48, 100)
	camera.zoom = Vector2(5, 5)
	world.add_child(camera)
	await frames(30)
	blue_at(Vector2(0, 120), 192.0)
	await frames(700)
	quit()
