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
	# 本套件不测试刺怪，清空刺格避免地图里的怪干扰既有断言。
	level.get_node("Spikes").clear()
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
	check(is_zero_approx(float(level.get_node("RoomCamera").get("fit_margin"))),
		"Camera fits the room with no extra margin")

	# 2b. 存档点被玩家接触激活后，发出一个持续存在的 5 格（80px）白色安全声场。
	if cp1 != null:
		level.player.reset_to(cp1.respawn_position())
		await frames(3)
		check(cp1.is_active(), "Touching the start checkpoint activates it")
	await frames(2)
	var cp_field: SoundField = null
	var cp_field_count := 0
	for child in level.sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() and child.emitter == null \
				and absf(child.side_length - 80.0) < 0.01:
			cp_field = child
			cp_field_count += 1
	check(cp_field != null, "Checkpoint maintains an 80 px sound field")
	if cp_field != null:
		check(cp_field.safe_for_player and not cp_field.lethal, "Checkpoint field is safe and non-lethal")
		check(cp_field.level == 0 and cp_field.color == Color.WHITE, "Checkpoint field is lv0 white")
		check(cp_field.emitter == null, "Checkpoint field has no emitter (doors ignore it)")
		check(cp_field.persistent and is_inf(cp_field.lifetime), "Checkpoint field is persistent")
	check(cp_field_count == 1, "Loaded checkpoint has exactly one field")
	var fade_alpha := cp_field.modulate.a if cp_field != null else 1.0
	await frames(40)
	check(cp_field != null and not cp_field.is_queued_for_deletion() \
		and not is_equal_approx(cp_field.modulate.a, fade_alpha),
		"Checkpoint field fades in and out visually")
	check(cp_field != null and cp_field.safe_for_player \
		and absf(cp_field.side_length - 80.0) < 0.01,
		"Checkpoint fade does not change its gameplay effect")
	var cp_field_id := cp_field.get_instance_id() if cp_field != null else 0
	await frames(130)
	check(is_instance_valid(cp_field) and not cp_field.is_queued_for_deletion() \
		and cp_field.get_instance_id() == cp_field_id,
		"Checkpoint field stays instead of pulsing")
	for child in level.sound_fields.get_children():
		if child is SoundField and child.emitter == null:
			child.queue_free()
	await frames(3)
	var rebuilt := false
	for child in level.sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() and child.emitter == null \
				and absf(child.side_length - 80.0) < 0.01:
			rebuilt = true
			break
	check(rebuilt, "Checkpoint recreates its field if removed")

	# 2c. 存档点旗子：激活的开旗，未激活的半透明闭旗。
	var active_flag := cp1.get_node_or_null("Sprite2D") as Sprite2D if cp1 != null else null
	check(cp1 != null and cp1.is_active() and active_flag != null \
		and active_flag.texture == Checkpoint.FLAG_OPEN \
		and is_equal_approx(active_flag.modulate.a, 1.0),
		"Active checkpoint shows the open flag")
	var inactive_cp: Checkpoint = null
	for node in _walk(level.get_node("Objects")):
		var checkpoint := node as Checkpoint
		if checkpoint != null and not checkpoint.is_active():
			inactive_cp = checkpoint
			break
	var inactive_flag: Sprite2D = null
	if inactive_cp != null:
		inactive_flag = inactive_cp.get_node_or_null("Sprite2D") as Sprite2D
	check(inactive_cp != null and inactive_flag != null \
		and inactive_flag.texture == Checkpoint.FLAG_CLOSE \
		and is_equal_approx(inactive_flag.modulate.a, 0.8),
		"Inactive checkpoint shows a translucent closed flag")

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
	check(level.breakables.has_cell(1, c1), "Leaving a room refreshes its glass")
	check(not level.breakables.has_cell(1, c2), "The entered room's glass stays broken")
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
	check(level.breakables.has_cell(1, c1), "Left room's glass stays restored")
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
	check(sprite != null and sprite.modulate.is_equal_approx(Color.WHITE),
		"Player is normal before touching noise")
	level.player.reset_to(target2)
	await frames(25)
	check(level.deaths == deaths_before, "Noise does not kill during the cooldown")
	check(sprite != null and sprite.modulate.g < 0.9 and sprite.modulate.b < 0.9,
		"Player tints red during the danger cooldown")
	for _i in range(150):
		await physics_frame
		if level.deaths > deaths_before:
			break
	check(level.deaths > deaths_before, "Standing in noise without a sound field kills the player")
	check(level.is_dead(), "Noise death waits for R before resetting")
	check(not level.player.visible, "Player is hidden on death")
	var die_stream: AudioStream = level.player.die_audio.stream if level.player.die_audio != null else null
	var death_sound_played := false
	for child in root.get_children():
		if child is AudioStreamPlayer and child.stream == die_stream and (child as AudioStreamPlayer).playing:
			death_sound_played = true
			(child as AudioStreamPlayer).stop()
			child.queue_free()
	check(die_stream != null and death_sound_played, "Player death plays the death sound")
	var restart_event := InputEventAction.new()
	restart_event.action = &"restart"
	restart_event.pressed = true
	level._unhandled_input(restart_event)
	check(sprite != null and sprite.modulate.is_equal_approx(Color.WHITE),
		"R clears the danger tint")
	await frames(3)
	check(not level.is_dead(), "R clears the dead state")
	check(level.player.visible, "R shows the player again")
	check(level.player.global_position.distance_to(level.get_checkpoint_anchor()) < 40.0,
		"R respawns at the checkpoint")
	check(level.breakables.has_cell(1, c2), "R restores the checkpoint room's glass")

	# 6. 房间裁剪：只处理玩家当前房间（Room3/Room4/Room5 联动）。
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
	check(cp1_node.process_mode == Node.PROCESS_MODE_DISABLED
		and cp3_node.process_mode == Node.PROCESS_MODE_DISABLED,
		"Checkpoints in other rooms are disabled")
	check(cp7_node.process_mode == Node.PROCESS_MODE_DISABLED and not cp7_node.is_visible_in_tree(),
		"Checkpoints in far rooms are disabled and hidden")
	check(is_instance_valid(cp7_node), "Far room objects are not freed")

	level.player.reset_to(room4.get_rect().get_center())
	await frames(3)
	var cp4_node := level.get_node("Objects/Checkpoint4") as Checkpoint
	var cp5_node := _checkpoint_in_room(room5)
	check(cp4_node.process_mode != Node.PROCESS_MODE_DISABLED,
		"Checkpoint4 activates after entering Room4")
	check(cp5_node != null and cp5_node.process_mode != Node.PROCESS_MODE_DISABLED,
		"Room5 loads together with Room4")
	check(cp3_node.process_mode != Node.PROCESS_MODE_DISABLED,
		"Room3 loads together with Room4")
	check(cp7_node.process_mode == Node.PROCESS_MODE_DISABLED,
		"Checkpoint7 stays disabled from Room4")

	var button6: Node = level.get_node("Buttons/ButtonOnce3")
	var button8: Node = level.get_node("Buttons/ButtonOnce5")
	var glass_lv1: TileMapLayer = level.breakables.lv1
	var g3: Vector2i = _cell_in_room(glass_lv1, room3_east)
	var g4: Vector2i = _cell_in_room(glass_lv1, room4)
	var g5: Vector2i = _cell_in_room(glass_lv1, room5)
	level.breakables.paint_cell(1, g3)
	level.breakables.paint_cell(1, g4)
	level.breakables.paint_cell(1, g5)
	level.breakables.refresh()
	level.breakables.break_in_rect(Rect2(glass_lv1.to_global(glass_lv1.map_to_local(g3)) - Vector2(8, 8), Vector2(16, 16)), 1)
	level.breakables.break_in_rect(Rect2(glass_lv1.to_global(glass_lv1.map_to_local(g4)) - Vector2(8, 8), Vector2(16, 16)), 1)
	level.breakables.break_in_rect(Rect2(glass_lv1.to_global(glass_lv1.map_to_local(g5)) - Vector2(8, 8), Vector2(16, 16)), 1)
	check(not level.breakables.has_cell(1, g3) and not level.breakables.has_cell(1, g4) \
		and not level.breakables.has_cell(1, g5),
		"Linked-room glass starts broken")
	level.player.reset_to(level.get_node("Rooms/Room6").get_rect().get_center())
	await frames(3)
	check(level.breakables.has_cell(1, g3) and level.breakables.has_cell(1, g4) \
		and level.breakables.has_cell(1, g5),
		"Room3/4/5 refresh together when leaving")
	check(button6.process_mode != Node.PROCESS_MODE_DISABLED
		and button8.process_mode != Node.PROCESS_MODE_DISABLED,
		"Room6 loads together with Room8")
	check(cp7_node.process_mode == Node.PROCESS_MODE_DISABLED,
		"Room7 stays disabled from Room6")
	level.player.reset_to(level.get_node("Rooms/Room8").get_rect().get_center())
	await frames(3)
	check(button6.process_mode != Node.PROCESS_MODE_DISABLED
		and button8.process_mode != Node.PROCESS_MODE_DISABLED,
		"Room8 loads together with Room6")

	var animal: Animal = level.get_node("Animals/Animal") as Animal
	var animal_home: Vector2 = animal._home_position
	animal.global_position = animal_home + Vector2(48, 0)
	level.reset_to_checkpoint()
	await frames(2)
	check(animal.global_position.distance_to(animal_home) < 0.5,
		"R reset returns animals to their home position")

	# 动物被驱赶换房：Room2 出生 → 移到 Room1 → 玩家进 Room1 → R 后留在 Room1。
	var mover: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(mover)
	mover.global_position = room2_start.get_rect().get_center()
	await frames(2)
	level.player.reset_to(room2_start.get_rect().get_center())
	await frames(3)
	mover.global_position = room1_west.get_rect().get_center()
	level.player.reset_to(room1_west.get_rect().get_center())
	await frames(3)
	var rebased_home: Vector2 = mover.home_position()
	level.reset_to_checkpoint()
	await frames(2)
	check(level.room_at(rebased_home) == room1_west
		and mover.global_position.distance_to(rebased_home) < 0.5,
		"Animal driven into another room respawns there after R")
	mover.queue_free()

	# Room3 的动物刷新点改记 Room4 存档点旁；只改记录，不移动本体。
	var redirected: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.get_node("Animals").add_child(redirected)
	redirected.global_position = cp3_node.respawn_position()
	await frames(2)
	level.player.reset_to(room3_east.get_rect().get_center())
	await frames(3)
	var expected_record := cp4_node.respawn_position() + Vector2(48, 0)
	check(level.room_at(redirected.home_position()) == room4,
		"Room3 animal records its home in Room4")
	check(redirected.home_position().distance_to(expected_record) < 0.5,
		"Room3 animal records beside Checkpoint4")
	check(level.room_at(redirected.global_position) == room3_east,
		"Recording Room4 does not move the animal")
	level.player.reset_to(room6.get_rect().get_center())
	await frames(3)
	check(level.room_at(redirected.global_position) == room3_east,
		"Leaving Room3 does not pull the animal back")
	level._set_checkpoint(room4, cp4_node.respawn_position(), cp4_node)
	level.reset_to_checkpoint()
	check(level.room_at(redirected.global_position) == room4,
		"R respawns the Room3-recorded animal in Room4")
	check(redirected.global_position.distance_to(expected_record) < 0.5,
		"R respawns the animal at the Room4 record point")
	check(redirected.visible and redirected.process_mode != Node.PROCESS_MODE_DISABLED,
		"Respawned animal is visible in Room4")
	await frames(1)
	redirected.queue_free()

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
	return clampf(fit, 1.0, 8.0)

func _other_room(rooms: Array[Room], start: Room) -> Room:
	for room in rooms:
		if room != start:
			return room
	return start
