extends SceneTree

var level: Node2D
var failures: Array[String] = []

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

func _run() -> void:
	level = load("res://scenes/levels/wave_jump_lab.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for _i in range(120):
		await physics_frame
		if level.player.is_on_floor():
			break
	level.noise.clear_all()
	level.breakables.clear_all()

	var sound_fields: Node2D = level.get_node("SoundFields")
	var barriers := BarrierField.new()
	barriers.tile_set = load("res://resources/barrier_tileset.tres")
	barriers.collision_enabled = true
	barriers.sound_fields = sound_fields
	level.add_child(barriers)

	var cell: Vector2i = barriers.local_to_map(barriers.to_local(level.player.global_position)) + Vector2i(2, 0)
	barriers.set_cell(cell, 0, Vector2i.ZERO)
	barriers.refresh_baseline()
	await frames(2)
	check(barriers.get_cell_source_id(cell) == -1, "Barrier starts hidden and non-solid")

	var barrier_world: Vector2 = barriers.to_global(barriers.map_to_local(cell))
	check(barriers.collision_enabled and barriers.tile_set.get_physics_layers_count() > 0,
		"Barrier tileset has a physics layer")

	var field := SoundField.new()
	field.side_length = 48.0
	field.lifetime = 2.0
	field.safe_for_player = true
	sound_fields.add_child(field)
	field.global_position = barrier_world
	await frames(2)
	check(barriers.get_cell_source_id(cell) != -1, "Barrier appears when covered by a sound field")

	# 屏障显形后阻挡玩家。
	var barrier_left := barrier_world.x - 8.0
	Input.action_press("move_right")
	await frames(40)
	Input.action_release("move_right")
	check(level.player.global_position.x <= barrier_left - 8.0 + 1.5,
		"Barrier blocks the player even while walking against it")

	# 任意声场（红色致命）也能激活。
	field.queue_free()
	await frames(3)
	var red := SoundField.new()
	red.side_length = 48.0
	red.lifetime = 2.0
	red.lethal = true
	red.safe_for_player = false
	red.color = Color(1.0, 0.2, 0.2, 1.0)
	sound_fields.add_child(red)
	red.global_position = barrier_world
	await frames(2)
	check(barriers.get_cell_source_id(cell) != -1, "Any sound field activates the barrier")

	# 声场结束后延迟 0.2 秒隐去。
	for child in sound_fields.get_children():
		child.queue_free()
	await frames(3)
	await frames(6)
	check(barriers.get_cell_source_id(cell) != -1, "Barrier stays briefly after the field ends")
	await frames(30)
	check(barriers.get_cell_source_id(cell) == -1, "Barrier hides after the 0.2 s delay")

	level.noise.clear_all()
	level.breakables.clear_all()
	print("\nBarrier checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
