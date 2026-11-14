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
	level = load("res://scenes/world/big_map.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(2)

	# 1. 玩家本体由 Sprite2D 贴图显示。
	var sprite: Sprite2D = level.player.get_node_or_null("Sprite2D")
	var has_sprite := sprite != null and sprite.texture != null and sprite.visible
	check(has_sprite, "Player has a visible sprite")

	var rooms: Array[Room] = level.get_rooms()
	check(rooms.size() >= 2, "Big map has at least two rooms")
	var room1: Room = rooms[0]
	var room2: Room = rooms[1]
	var camera: Camera2D = level.get_node("Camera")
	var viewport_size := camera.get_viewport_rect().size

	# 2. 初始房间、初始存档点、初始相机取景。
	var start_room: Room = level.room_at(level.player.global_position)
	check(start_room == room1, "Player starts inside the first room")
	var cp1 := _checkpoint_in_room(room1)
	if cp1 != null:
		check(level.get_checkpoint_anchor().distance_to(cp1.respawn_position()) < 0.5,
			"Start checkpoint is the first room's Checkpoint")
	else:
		check(level.get_checkpoint_anchor().distance_to(level.player.global_position) < 1.0,
			"Start checkpoint records the player position")
	check(level.get_checkpoint_room() == start_room, "Start checkpoint belongs to the player's room")
	check(camera.global_position.distance_to(room1.get_rect().get_center()) < 2.0,
		"Camera starts centered on the first room")
	check(absf(camera.zoom.x - _fit_zoom(room1, viewport_size)) < 0.02,
		"Camera zooms to fit the first room")

	# 3. 声场视觉：在 expand_duration 内从中心扩到目标边长（判定仍是满尺寸，不随视觉变化）。
	var field := SoundField.new()
	field.side_length = 96.0
	level.sound_fields.add_child(field)
	await frames(2)
	check(field.current_side > 0.0 and field.current_side < 96.0, "Sound field expands from the center")
	var expand_frames := int(ceil(field.expand_duration * float(Engine.physics_ticks_per_second))) + 2
	await frames(expand_frames)
	check(absf(field.current_side - 96.0) < 0.5,
		"Sound field reaches target size in %.2f s" % field.expand_duration)
	field.queue_free()

	# 4. 两间房各放一块玻璃，打碎后进入第二间房按 R：只还原第二间。
	var lv1: TileMapLayer = level.breakables.lv1
	var c1: Vector2i = _cell_in_room(lv1, room1)
	var c2: Vector2i = _cell_in_room(lv1, room2)
	level.breakables.paint_cell(1, c1)
	level.breakables.paint_cell(1, c2)
	level.breakables.refresh()
	var p1: Vector2 = lv1.to_global(lv1.map_to_local(c1))
	var p2: Vector2 = lv1.to_global(lv1.map_to_local(c2))
	level.breakables.break_in_rect(Rect2(p1 - Vector2(8, 8), Vector2(16, 16)), 1)
	level.breakables.break_in_rect(Rect2(p2 - Vector2(8, 8), Vector2(16, 16)), 1)
	check(not level.breakables.has_cell(1, c1) and not level.breakables.has_cell(1, c2),
		"Both glass cells are broken")

	var cp2 := _checkpoint_in_room(room2)
	var target2: Vector2 = cp2.respawn_position() if cp2 != null else room2.get_rect().get_center()
	level.player.reset_to(target2)
	await frames(10)
	check(level.get_checkpoint_room() == room2, "Entering the second room binds its checkpoint")
	if cp2 != null:
		check(level.get_checkpoint_anchor().distance_to(cp2.respawn_position()) < 0.5,
			"Checkpoint anchor follows the second room's Checkpoint")
	await create_timer(0.8).timeout
	check(camera.global_position.distance_to(room2.get_rect().get_center()) < 2.0,
		"Camera tweens to the second room center")
	check(absf(camera.zoom.x - _fit_zoom(room2, viewport_size)) < 0.02,
		"Camera keeps the second room fit zoom")

	level.reset_to_checkpoint()
	var respawn_position: Vector2 = level.player.global_position
	await frames(2)
	check(not level.breakables.has_cell(1, c1), "Reset leaves the first room's glass broken")
	check(level.breakables.has_cell(1, c2), "Reset restores the second room's glass")
	check(respawn_position.distance_to(level.get_checkpoint_anchor()) < 0.1,
		"Reset respawns at the checkpoint")
	check(camera.global_position.distance_to(room2.get_rect().get_center()) < 2.0,
		"Reset snaps camera to the checkpoint room")

	# 5. 噪音内站桩死亡后回到存档点。
	level.breakables.break_in_rect(Rect2(p2 - Vector2(8, 8), Vector2(16, 16)), 1)
	var noise_layer: TileMapLayer = level.noise
	var base: Vector2i = noise_layer.local_to_map(noise_layer.to_local(target2))
	var noise_cells: Array[Vector2i] = []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			noise_cells.append(base + Vector2i(dx, dy))
	level.noise.paint_cells(noise_cells)
	var deaths_before: int = level.deaths
	level.player.reset_to(target2)
	await frames(25)
	check(level.deaths > deaths_before, "Standing in noise without a sound field kills the player")
	check(level.player.global_position.distance_to(level.get_checkpoint_anchor()) < 40.0,
		"Death respawns at the checkpoint")
	check(level.breakables.has_cell(1, c2), "Death restores the checkpoint room's glass")

	level.noise.clear_all()
	level.breakables.clear_all()
	print("\nBig map checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _checkpoint_in_room(room: Room) -> Checkpoint:
	var objects := level.get_node_or_null("Objects")
	if objects == null or room == null:
		return null
	for node in _walk(objects):
		if node is Checkpoint:
			var checkpoint := node as Checkpoint
			if room.contains_world_point(checkpoint.global_position):
				return checkpoint
	return null

func _walk(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_walk(child))
	return result

func _cell_in_room(layer: TileMapLayer, room: Room) -> Vector2i:
	return layer.local_to_map(layer.to_local(room.get_rect().get_center()))

func _fit_zoom(room: Room, viewport_size: Vector2) -> float:
	var size := room.get_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	var fit := minf(viewport_size.x / size.x, viewport_size.y / size.y)
	return clampf(fit * 0.92, 1.0, 8.0)
