extends SceneTree

var level: Node2D
var failures: Array[String] = []
var waves: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, text: String) -> void:
	if value:
		print("PASS  ", text)
	else:
		failures.append(text)
		push_error("FAIL  " + text)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func is_on_grid(value: float) -> bool:
	return absf(value / 16.0 - roundf(value / 16.0)) < 0.001

func settle(limit: int = 180) -> void:
	for _i in range(limit):
		await physics_frame
		if level.player.is_on_floor():
			return

func release_all() -> void:
	for action in ["move_left", "move_right", "jump"]:
		Input.action_release(action)

func record_wave(origin: Vector2, side: float, level_value: int, kind: String) -> void:
	waves.append({"origin": origin, "side": side, "level": level_value, "kind": kind})

func clear_records() -> void:
	waves.clear()

func count_waves(kind: String) -> int:
	var total := 0
	for wave in waves:
		if wave["kind"] == kind:
			total += 1
	return total

func wave_sides(kind: String) -> Array[float]:
	var sides: Array[float] = []
	for wave in waves:
		if wave["kind"] == kind:
			sides.append(wave["side"])
	return sides

func wave_levels(kind: String) -> Array[int]:
	var levels: Array[int] = []
	for wave in waves:
		if wave["kind"] == kind:
			levels.append(wave["level"])
	return levels

func wave_origins(kind: String) -> Array[Vector2]:
	var origins: Array[Vector2] = []
	for wave in waves:
		if wave["kind"] == kind:
			origins.append(wave["origin"])
	return origins

func _run() -> void:
	level = load("res://scenes/levels/wave_jump_lab.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.player.wave_emitted.connect(record_wave)

	check(SoundField.color_for_level(0) == Color.WHITE, "lv0 player sound field is white")
	var lv1_blue := SoundField.color_for_level(1)
	var lv2_yellow := SoundField.color_for_level(2)
	check(lv1_blue.b > lv1_blue.r and lv1_blue.b > lv1_blue.g, "lv1 player sound field is blue")
	check(lv2_yellow.r > 0.9 and lv2_yellow.g > 0.8 and lv2_yellow.b < 0.4, "lv2 player sound field is yellow")

	# 0. Cold start must not measure a drop from y=0.
	await frames(30)
	check(waves.is_empty(), "Cold start emits no sonar")

	level.restart_run()
	await settle()
	level.noise.clear_all()
	level.breakables.clear_all()
	var ground_y: float = level.player.position.y
	var lv0_side: float = level.player.walk_wave_side_cells * 16.0
	var lv1_side: float = level.player.landing_lv1_side_cells * 16.0
	var lv2_side: float = level.player.landing_lv2_side_cells * 16.0
	# 左侧墙世界右缘 x=128；按当前碰撞体宽度计算接触点。
	var player_shape: RectangleShape2D = level.player.get_node("CollisionShape2D").shape
	var contact_x: float = 128.0 + player_shape.size.x * 0.5

	# 1. Jump apex follows jump_height_tiles; landing is a level-1 sound field and never pushes.
	clear_records()
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	check(count_waves("jump") == 1, "Jump takeoff emits one lv0 sound field")
	var takeoff_sides := wave_sides("jump")
	var takeoff_levels := wave_levels("jump")
	check(takeoff_sides.size() >= 1 and absf(takeoff_sides[0] - lv0_side) < 0.01
		and takeoff_levels[0] == 0, "Jump takeoff is lv0 with the configured walk side (%.0f px)" % lv0_side)
	var apex_y: float = level.player.position.y
	for _i in range(220):
		await physics_frame
		apex_y = minf(apex_y, level.player.position.y)
	var jump_px: float = level.player.jump_height_tiles * 16.0
	check(absf(ground_y - apex_y - jump_px) <= 1.0,
		"Jump apex equals jump_height_tiles × 16 px (%.0f px)" % jump_px)
	check(count_waves("landing") == 1, "Jump landing emits exactly one landing sound field")
	var jump_sides := wave_sides("landing")
	var jump_levels := wave_levels("landing")
	check(jump_sides.size() >= 1 and absf(jump_sides[0] - lv1_side) < 0.01, "Jump landing emits the configured lv1 side (%.0f px)" % lv1_side)
	check(jump_levels.size() >= 1 and jump_levels[0] == 1, "Jump landing is a level-1 sound field")
	check(level.player.is_on_floor() and absf(level.player.position.y - ground_y) < 1.0, "Landing sonar does not bounce the player")
	check(count_waves("ceiling") == 0, "Open-air jump emits no ceiling wave")

	# 1b. Jumping into a ceiling emits one lv1 blue wave.
	level.restart_run()
	await settle()
	var ceiling := StaticBody2D.new()
	ceiling.collision_layer = 1
	ceiling.collision_mask = 0
	var ceiling_shape := CollisionShape2D.new()
	var ceiling_rect := RectangleShape2D.new()
	ceiling_rect.size = Vector2(64, 16)
	ceiling_shape.shape = ceiling_rect
	ceiling.add_child(ceiling_shape)
	level.add_child(ceiling)
	ceiling.global_position = Vector2(level.player.global_position.x, ground_y - 40.0)
	await frames(2)
	clear_records()
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(60)
	var ceiling_levels := wave_levels("ceiling")
	var ceiling_sides := wave_sides("ceiling")
	check(count_waves("ceiling") == 1, "Jumping into a ceiling emits exactly one ceiling wave")
	check(ceiling_levels.size() == 1 and ceiling_levels[0] == 1,
		"Ceiling wave is a level-1 sound field")
	check(ceiling_sides.size() == 1 and absf(ceiling_sides[0] - lv1_side) < 0.01,
		"Ceiling wave uses the configured lv1 side (%.0f px)" % lv1_side)
	ceiling.queue_free()
	await frames(2)

	# 1c. A ceiling with headroom still emits lv1.
	level.restart_run()
	await settle()
	var low_ceiling := StaticBody2D.new()
	low_ceiling.collision_layer = 1
	low_ceiling.collision_mask = 0
	var low_shape := CollisionShape2D.new()
	var low_rect := RectangleShape2D.new()
	low_rect.size = Vector2(64, 16)
	low_shape.shape = low_rect
	low_ceiling.add_child(low_shape)
	level.add_child(low_ceiling)
	low_ceiling.global_position = Vector2(level.player.global_position.x, ground_y - 24.0)
	await frames(2)
	clear_records()
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(40)
	var low_levels := wave_levels("ceiling")
	var low_sides := wave_sides("ceiling")
	check(count_waves("ceiling") == 1, "Low-ceiling bump emits exactly one ceiling wave")
	check(low_levels.size() == 1 and low_levels[0] == 1,
		"Ceiling with headroom is a level-1 sound field")
	check(low_sides.size() == 1 and absf(low_sides[0] - lv1_side) < 0.01,
		"Ceiling with headroom uses the configured lv1 side (%.0f px)" % lv1_side)
	low_ceiling.queue_free()
	await frames(2)

	# 1d. Jumping with zero headroom emits a 2-second lv2 wave.
	level.restart_run()
	await settle()
	var zero_ceiling := StaticBody2D.new()
	zero_ceiling.collision_layer = 1
	zero_ceiling.collision_mask = 0
	var zero_shape := CollisionShape2D.new()
	var zero_rect := RectangleShape2D.new()
	zero_rect.size = Vector2(64, 16)
	zero_shape.shape = zero_rect
	zero_ceiling.add_child(zero_shape)
	level.add_child(zero_ceiling)
	zero_ceiling.global_position = Vector2(level.player.global_position.x, ground_y - 13.0)
	await frames(2)
	clear_records()
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(40)
	var zero_levels := wave_levels("ceiling")
	var zero_sides := wave_sides("ceiling")
	check(count_waves("ceiling") == 1, "Zero-headroom bump emits exactly one ceiling wave")
	check(zero_levels.size() == 1 and zero_levels[0] == 2,
		"Zero-headroom bump is a level-2 sound field")
	check(zero_sides.size() == 1 and absf(zero_sides[0] - lv2_side) < 0.01,
		"Zero-headroom wave uses the configured lv2 side (%.0f px)" % lv2_side)
	var lv2_ceiling: SoundField = null
	for child in level.sound_fields.get_children():
		if child is SoundField and child.level == 2:
			lv2_ceiling = child
			break
	check(lv2_ceiling != null and lv2_ceiling.lifetime == SoundField.LV2_LIFETIME,
		"Zero-headroom wave lasts 2 seconds")
	zero_ceiling.queue_free()
	await frames(2)

	# 2. Drop tiers: 1 -> lv0/96, 2-3 -> lv1/160, 4 -> lv2/224.
	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 32.0))
	await frames(150)
	check(count_waves("landing") == 1, "32 px drop emits one landing sound field")
	check(wave_sides("landing")[0] == lv0_side and wave_levels("landing")[0] == 0, "32 px drop is lv0 / %.0f px" % lv0_side)

	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 64.0))
	await frames(150)
	check(count_waves("landing") == 1, "64 px drop emits one landing sound field")
	check(wave_sides("landing")[0] == lv1_side and wave_levels("landing")[0] == 1, "64 px drop is lv1 / %.0f px" % lv1_side)
	check(level.player.is_on_floor(), "64 px drop settles on the floor")

	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 96.0))
	await frames(150)
	check(count_waves("landing") == 1, "96 px drop emits one landing sound field")
	check(wave_sides("landing")[0] == lv1_side and wave_levels("landing")[0] == 1, "96 px drop is lv1 / %.0f px" % lv1_side)

	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 128.0))
	await frames(150)
	check(count_waves("landing") == 1, "128 px drop emits one landing sound field")
	check(wave_sides("landing")[0] == lv2_side and wave_levels("landing")[0] == 2, "128 px drop is lv2 / %.0f px" % lv2_side)
	var lv2_field: SoundField = null
	for child in level.sound_fields.get_children():
		if child is SoundField and child.level == 2:
			lv2_field = child
			break
	check(lv2_field != null, "128 px drop leaves a level-2 sound field on the map")
	check(lv2_field != null and lv2_field.lifetime == SoundField.LV2_LIFETIME and not lv2_field.persistent,
		"Level-2 field lasts 2 seconds and is not persistent")

	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 8.0))
	await frames(120)
	check(count_waves("landing") == 0, "8 px drop emits no landing sound field")
	check(level.player.is_on_floor(), "Player settles after an 8 px drop")

	# 3. Walking emits a lv0 96 px sound field every 32 px.
	level.restart_run()
	await settle()
	var lv2_after_reset := false
	for child in level.sound_fields.get_children():
		if child is SoundField and child.level == 2:
			lv2_after_reset = true
	check(not lv2_after_reset, "Restart clears the level-2 field")
	clear_records()
	var start_x: float = level.player.position.x
	Input.action_press("move_right")
	for _i in range(240):
		await physics_frame
		if level.player.position.x - start_x >= 65.0:
			break
	Input.action_release("move_right")
	await frames(25)
	check(count_waves("step") == 3, "Walking about 65 px emits three step sound fields")
	var step_sides := wave_sides("step")
	var step_levels := wave_levels("step")
	var sides_ok := step_sides.size() == 3
	for side in step_sides:
		sides_ok = sides_ok and absf(side - lv0_side) < 0.01
	check(sides_ok, "Every step sound field is the configured lv0 side (%.0f px)" % lv0_side)
	var levels_ok := step_levels.size() == 3
	for level_value in step_levels:
		levels_ok = levels_ok and level_value == 0
	check(levels_ok, "Step sound fields are lv0")
	check(count_waves("landing") == 0 and waves.size() == count_waves("step"), "Walking emits only step sound fields")
	check(absf(level.player.position.y - ground_y) < 1.0, "Step sound fields do not push the player")
	var step_origins := wave_origins("step")
	var spacing_ok := step_origins.size() == 3
	for i in range(1, step_origins.size()):
		spacing_ok = spacing_ok and absf(absf(step_origins[i].x - step_origins[i - 1].x) - 32.0) <= 3.0
	check(spacing_ok, "Step sound fields are fixed 32 px apart")

	# 3b. Generated fields snap their edges to the 16 px grid.
	var probe := SoundField.snap_origin_to_grid(Vector2(905, 485), 96.0)
	check(is_on_grid(probe.x - 48.0) and is_on_grid(probe.y - 48.0),
		"snap_origin_to_grid puts the field's top-left corner on the grid")
	var generated_field: SoundField = null
	for child in level.sound_fields.get_children():
		if child is SoundField and child.emitter == level.player and child.level == 0:
			generated_field = child
	check(generated_field != null, "Walking leaves a generated sound field")
	if generated_field != null:
		var field_rect := generated_field.get_rect()
		check(is_on_grid(field_rect.position.x) and is_on_grid(field_rect.position.y),
			"Generated sound field edges align to the 16 px grid")

	# 4. Walking into the wall emits no landing sonar.
	level.restart_run()
	await frames(10)
	level.player.reset_to(Vector2(contact_x + 40.0, ground_y))
	await frames(2)
	clear_records()
	Input.action_press("move_left")
	await frames(90)
	Input.action_release("move_left")
	check(absf(level.player.position.x - contact_x) <= 1.0, "Walking into the wall stops at the collision boundary")
	check(count_waves("landing") == 0, "Walking into a wall emits no landing sound field")
	check(count_waves("step") >= 4, "Pressing into a wall keeps emitting step sound fields")
	check(count_waves("ceiling") == 0, "Walking into a wall emits no ceiling wave")

	# 5. Double-tapping a direction gains no extra speed.
	level.restart_run()
	await frames(10)
	level.player.reset_to(Vector2(200, ground_y))
	await frames(2)
	Input.action_press("move_right")
	await physics_frame
	Input.action_release("move_right")
	await physics_frame
	Input.action_press("move_right")
	var max_speed := 0.0
	for _i in range(40):
		await physics_frame
		max_speed = maxf(max_speed, absf(level.player.velocity.x))
	Input.action_release("move_right")
	check(max_speed <= 251.0, "Double-tapping does not exceed walk speed")
	await frames(20)
	check(level.player.is_on_floor(), "Double-tapping keeps the player grounded")

	# 6. Breakable tiles break only from a same-level wave.
	level.breakables.clear_all()
	var lv1_cell := Vector2i(54, 31)
	var lv2_cell := Vector2i(57, 31)
	level.breakables.paint_cell(1, lv1_cell)
	level.breakables.paint_cell(2, lv2_cell)
	level.breakables.refresh()
	await frames(2)
	check(level.breakables.has_cell(1, lv1_cell) and level.breakables.has_cell(2, lv2_cell), "Both test cells start intact")

	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 64.0))
	await frames(150)
	check(not level.breakables.has_cell(1, lv1_cell), "Level-1 wave breaks the level-1 cell")
	check(level.breakables.has_cell(2, lv2_cell), "Level-1 wave leaves the level-2 cell intact")

	level.breakables.reset()
	await frames(2)
	check(level.breakables.has_cell(1, lv1_cell) and level.breakables.has_cell(2, lv2_cell), "Reset restores broken cells")
	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 32.0))
	await frames(150)
	check(level.breakables.has_cell(1, lv1_cell), "Level-0 wave cannot break a level-1 cell")
	check(level.breakables.has_cell(2, lv2_cell), "Level-0 wave cannot break a level-2 cell")

	clear_records()
	level.player.reset_to(Vector2(900, ground_y - 128.0))
	await frames(150)
	check(not level.breakables.has_cell(2, lv2_cell), "Level-2 wave breaks the level-2 cell")
	check(level.breakables.has_cell(1, lv1_cell), "Level-2 wave leaves the level-1 cell intact")
	level.breakables.clear_all()

	# 7. Noise field survival with a 0.5 s grace.
	level.noise.clear_all()
	var noise_cells: Array[Vector2i] = []
	for x in range(24, 44):
		for y in range(20, 34):
			noise_cells.append(Vector2i(x, y))
	level.noise.paint_cells(noise_cells)
	await frames(2)

	level.restart_run()
	await frames(5)
	var deaths_before: int = level.deaths
	level.teleport_player(Vector2(400, ground_y))
	await frames(5)
	check(level.deaths == deaths_before, "Standing in noise survives the first 0.5 s")
	await frames(20)
	check(level.deaths == deaths_before, "Noise does not kill during the 0.5 s cooldown")
	var died := false
	for _i in range(150):
		await physics_frame
		if level.deaths > deaths_before:
			died = true
			break
	check(died and level.deaths == deaths_before + 1, "Noise kills once the 0.5 s cooldown ends")
	check(absf(level.player.position.x - 320.0) < 5.0, "Death respawns at the level start")

	level.restart_run()
	await frames(5)
	deaths_before = level.deaths
	level.teleport_player(Vector2(400, ground_y))
	await frames(3)
	Input.action_press("move_right")
	await frames(120)
	Input.action_release("move_right")
	check(level.deaths == deaths_before, "Continuous walking inside noise stays safe")

	# 7b. Red noise cells under an active white frame are temporarily hidden.
	level.restart_run()
	await frames(5)
	check(not level.noise.is_cell_hidden(Vector2i(24, 33)), "Noise cells start visible")
	clear_records()
	Input.action_press("move_right")
	for _i in range(120):
		await physics_frame
		if level.player.position.x >= 400.0 and count_waves("step") > 0:
			break
	Input.action_release("move_right")
	await frames(2)
	var hidden_step_origins := wave_origins("step")
	var hidden_cell: Vector2i = level.noise.local_to_map(level.noise.to_local(hidden_step_origins.back()))
	check(level.noise.is_cell_hidden(hidden_cell), "Noise cells inside a white frame turn invisible")
	level.teleport_player(Vector2(320, ground_y))
	await frames(80)
	check(not level.noise.is_cell_hidden(hidden_cell), "Noise cells reappear after the frame expires")

	deaths_before = level.deaths
	level.teleport_player(Vector2(400, ground_y))
	await frames(3)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	died = false
	for _i in range(400):
		await physics_frame
		if level.deaths > deaths_before:
			died = true
			break
	check(died and level.deaths == deaths_before + 1, "Jumping out of the frames in noise restarts the run")

	level.restart_run()
	await frames(5)
	deaths_before = level.deaths
	await frames(120)
	check(level.deaths == deaths_before, "Standing outside noise is always safe")

	# 7c. A noise cell is hidden only when fully covered by a single field.
	level.noise.clear_all()
	var cover_cell := Vector2i(30, 33)
	var cover_cells: Array[Vector2i] = [cover_cell]
	level.noise.paint_cells(cover_cells)
	await frames(2)
	var cover_center: Vector2 = level.noise.to_global(level.noise.map_to_local(cover_cell))
	var cover_rect := Rect2(cover_center - Vector2(8, 8), Vector2(16, 16))
	var partial := Rect2(cover_rect.position + Vector2(8, 0), cover_rect.size)
	var partial_rects: Array[Rect2] = [partial]
	level.noise.sync_visibility(partial_rects)
	check(not level.noise.is_cell_hidden(cover_cell), "Partially overlapping field does not hide a noise cell")
	var full_rects: Array[Rect2] = [cover_rect.grow(2.0)]
	level.noise.sync_visibility(full_rects)
	check(level.noise.is_cell_hidden(cover_cell), "Fully covering field hides a noise cell")
	var no_rects: Array[Rect2] = []
	level.noise.sync_visibility(no_rects)
	check(not level.noise.is_cell_hidden(cover_cell), "Clearing fields restores the noise cell")

	# 7d. Body-rect noise contact helper.
	check(level.noise.touches_rect(cover_rect.grow(-4.0)), "Noise touches a body rect inside a cell")
	check(level.noise.touches_rect(Rect2(cover_rect.position + Vector2(-2, 4), Vector2(4, 8))),
		"Noise touches a body rect overlapping a cell edge")
	check(not level.noise.touches_rect(Rect2(cover_rect.end + Vector2(4, 4), Vector2(12, 12))),
		"A body rect outside noise does not touch it")

	# 7e. Body-edge contact starts the 0.5 s cooldown while the center stays outside noise.
	level.noise.clear_all()
	var edge_cell: Vector2i = level.noise.local_to_map(level.noise.to_local(Vector2(344, ground_y)))
	var edge_cells: Array[Vector2i] = [edge_cell]
	level.noise.paint_cells(edge_cells)
	level.teleport_player(Vector2(334, ground_y))
	await frames(2)
	deaths_before = level.deaths
	await frames(25)
	check(level.deaths == deaths_before, "Body-edge noise contact survives the cooldown")
	for _i in range(150):
		await physics_frame
		if level.deaths > deaths_before:
			break
	check(level.deaths == deaths_before + 1, "Body-edge noise contact kills after the cooldown")
	check(absf(level.player.position.x - 320.0) < 5.0, "Body-edge death respawns at the level start")
	level.noise.clear_all()

	# 8. Left-click debug teleport.
	level.restart_run()
	await frames(5)
	var target := Vector2(450, 380)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.position = level.world_to_screen(target)
	click.global_position = click.position
	root.push_input(click, true)
	await physics_frame
	if level.player.global_position.distance_to(target) > 2.0:
		print("Teleport diagnostic: target=", target, " player=", level.player.global_position, " screen=", click.position)
	check(level.player.global_position.distance_to(target) <= 2.0, "Left-click teleports the player to the clicked point")

	release_all()
	print("\nKeyboard movement checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
