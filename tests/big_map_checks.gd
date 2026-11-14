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
	# 显式指定一个与玩家初始位置不同的起始房间，验证 Start Room 功能。
	var rooms_before: Array[Room] = []
	for child in level.get_node("Rooms").get_children():
		if child is Room:
			rooms_before.append(child)
	var authored_room := RoomRegistry.room_at(rooms_before, level.get_node("Player").global_position)
	var start_target: Room = rooms_before[0]
	for room in rooms_before:
		if room != authored_room:
			start_target = room
			break
	level.start_room = start_target
	root.add_child(level)
	current_scene = level
	await frames(2)

	# 1. 玩家本体由 Sprite2D 贴图显示。
	var sprite: Sprite2D = level.player.get_node_or_null("Sprite2D")
	var has_sprite := sprite != null and sprite.texture != null and sprite.visible
	check(has_sprite, "Player has a visible sprite")

	var rooms: Array[Room] = level.get_rooms()
	check(rooms.size() >= 2, "Big map has at least two rooms")
	var start_room: Room = level.room_at(level.player.global_position)
	check(start_room != null, "Player starts inside a room")
	if level.start_room != null:
		check(start_room == level.start_room, "Player starts in the configured Start Room")
	var room1: Room = start_room
	var room2: Room = _other_room(rooms, start_room)
	check(room1 != null and room2 != null and room1 != room2, "Start room and another room exist")
	var camera: Camera2D = level.get_node("Camera")
	var viewport_size := camera.get_viewport_rect().size

	# 2. 初始房间、初始存档点、初始相机取景。
	var cp1 := _checkpoint_in_room(room1)
	if cp1 != null:
		check(level.get_checkpoint_anchor().distance_to(cp1.respawn_position()) < 0.5,
			"Start checkpoint is the start room's Checkpoint")
	else:
		check(level.get_checkpoint_anchor().distance_to(level.player.global_position) < 1.0,
			"Start checkpoint records the player position")
	check(level.get_checkpoint_room() == start_room, "Start checkpoint belongs to the player's room")
	check(camera.global_position.distance_to(room1.get_rect().get_center()) < 2.0,
		"Camera starts centered on the start room")
	check(absf(camera.zoom.x - _fit_zoom(room1, viewport_size)) < 0.02,
		"Camera zooms to fit the start room")

	# 2b. 每个存档点每 0.2 秒发一次 5 格（80px）白色安全声场。
	await frames(2)
	var cp_field: SoundField = null
	for child in level.sound_fields.get_children():
		if child is SoundField and child.emitter == null and absf(child.side_length - 80.0) < 0.01:
			cp_field = child
			break
	check(cp_field != null, "Checkpoint emits an 80 px sound field")
	if cp_field != null:
		check(cp_field.safe_for_player and not cp_field.lethal, "Checkpoint field is safe and non-lethal")
		check(cp_field.level == 0 and cp_field.color == Color.WHITE, "Checkpoint field is lv0 white")
		check(cp_field.emitter == null, "Checkpoint field has no emitter (doors ignore it)")
	for child in level.sound_fields.get_children():
		if child is SoundField and child.emitter == null:
			child.queue_free()
	await frames(30)
	var reemitted := false
	for child in level.sound_fields.get_children():
		if child is SoundField and child.emitter == null and absf(child.side_length - 80.0) < 0.01:
			reemitted = true
			break
	check(reemitted, "Checkpoint re-emits within 0.2 s")

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
	var anchor_before: Vector2 = level.get_checkpoint_anchor()
	level.player.reset_to(room2.get_rect().get_center())
	await frames(10)
	check(level.get_checkpoint_anchor().distance_to(anchor_before) < 0.5,
		"Entering a room without touching its checkpoint keeps the old anchor")
	level.player.reset_to(target2)
	await frames(10)
	if cp2 != null:
		check(level.get_checkpoint_room() == room2, "Touching the second room's checkpoint binds it")
		check(level.get_checkpoint_anchor().distance_to(cp2.respawn_position()) < 0.5,
			"Checkpoint anchor follows the second room's Checkpoint")
	else:
		check(level.get_checkpoint_anchor().distance_to(anchor_before) < 0.5,
			"A room without a checkpoint leaves the old anchor")
	await create_timer(0.8).timeout
	check(camera.global_position.distance_to(room2.get_rect().get_center()) < 2.0,
		"Camera tweens to the second room center")
	check(absf(camera.zoom.x - _fit_zoom(room2, viewport_size)) < 0.02,
		"Camera keeps the second room fit zoom")

	level.reset_to_checkpoint()
	var respawn_position: Vector2 = level.player.global_position
	await frames(2)
	check(not level.breakables.has_cell(1, c1), "Reset leaves the start room's glass broken")
	check(level.breakables.has_cell(1, c2), "Reset restores the other room's glass")
	check(respawn_position.distance_to(level.get_checkpoint_anchor()) < 0.1,
		"Reset respawns at the checkpoint")
	check(camera.global_position.distance_to(room2.get_rect().get_center()) < 2.0,
		"Reset snaps camera to the checkpoint room")

	# 5. 噪音内站桩死亡后回到存档点。
	# 存档点声场会把存档点变成永久安全区；本测试需要关闭。
	for node in _walk(level.get_node("Objects")):
		if node is Checkpoint:
			node.fields_enabled = false
	for child in level.sound_fields.get_children():
		if child is SoundField and child.emitter == null:
			child.queue_free()
	await frames(2)

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
	check(level.deaths == deaths_before, "Noise does not kill during the 0.5 s cooldown")
	for _i in range(150):
		await physics_frame
		if level.deaths > deaths_before:
			break
	check(level.deaths > deaths_before, "Standing in noise without a sound field kills the player")
	check(level.player.global_position.distance_to(level.get_checkpoint_anchor()) < 40.0,
		"Death respawns at the checkpoint")
	check(level.breakables.has_cell(1, c2), "Death restores the checkpoint room's glass")

	# 6. 房间裁剪：只处理玩家房间 + 上下左右相邻房间的物体。
	var room2_start: Room = level.get_node("Rooms/Room2")
	var room1_west: Room = level.get_node("Rooms/Room1")
	var room3_east: Room = level.get_node("Rooms/Room3")
	var room4: Room = level.get_node("Rooms/Room4")
	var room5: Room = level.get_node("Rooms/Room5")
	var room6: Room = level.get_node("Rooms/Room6")
	check(RoomRegistry.is_orthogonal_neighbor(room1_west.get_rect(), room2_start.get_rect()),
		"Room1 and Room2 are orthogonal neighbors")
	check(not RoomRegistry.is_orthogonal_neighbor(room3_east.get_rect(), room5.get_rect()),
		"Room3 and Room5 are not orthogonal neighbors")
	check(not RoomRegistry.is_orthogonal_neighbor(room4.get_rect(), room6.get_rect()),
		"Room4 and Room6 are not orthogonal neighbors")

	level.player.reset_to(room2_start.get_rect().get_center())
	await frames(3)
	var cp2_node := level.get_node("Objects/Checkpoint2") as Checkpoint
	var cp1_node := level.get_node("Objects/Checkpoint1") as Checkpoint
	var cp3_node := level.get_node("Objects/Checkpoint3") as Checkpoint
	var cp7_node := level.get_node("Objects/Checkpoint7") as Checkpoint
	check(cp2_node.process_mode != Node.PROCESS_MODE_DISABLED and cp2_node.is_visible_in_tree(),
		"Checkpoint in the player's room stays active")
	check(cp1_node.process_mode != Node.PROCESS_MODE_DISABLED
		and cp3_node.process_mode != Node.PROCESS_MODE_DISABLED,
		"Checkpoints in neighbor rooms stay active")
	check(cp7_node.process_mode == Node.PROCESS_MODE_DISABLED and not cp7_node.is_visible_in_tree(),
		"Checkpoints in far rooms are disabled and hidden")
	check(is_instance_valid(cp7_node), "Far room objects are not freed")

	level.player.reset_to(room4.get_rect().get_center())
	await frames(3)
	var cp4_node := level.get_node("Objects/Checkpoint4") as Checkpoint
	var cp5_node := level.get_node("Objects/Checkpoint5") as Checkpoint
	check(cp4_node.process_mode != Node.PROCESS_MODE_DISABLED,
		"Checkpoint4 activates after entering Room4")
	check(cp5_node.process_mode != Node.PROCESS_MODE_DISABLED,
		"Checkpoint5 (neighbor above) stays active from Room4")
	check(cp7_node.process_mode == Node.PROCESS_MODE_DISABLED,
		"Checkpoint7 stays disabled from Room4")

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

func _other_room(rooms: Array[Room], start: Room) -> Room:
	for room in rooms:
		if room != start:
			return room
	return start
