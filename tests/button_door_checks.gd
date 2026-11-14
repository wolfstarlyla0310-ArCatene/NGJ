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

func _spawn_field(sound_fields: Node2D, pos: Vector2, side: float, field_level: int) -> SoundField:
	var field := SoundField.new()
	field.side_length = side
	field.lifetime = 2.0
	field.level = field_level
	field.safe_for_player = true
	sound_fields.add_child(field)
	field.global_position = pos
	return field

func _typed_cells(cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	return cells

func _run() -> void:
	level = load("res://scenes/world/big_map.tscn").instantiate()
	level.start_room = level.get_node("Rooms/Room1")
	root.add_child(level)
	current_scene = level
	await frames(2)

	var door_tiles: TileMapLayer = level.get_node("DoorTiles")
	var buttons_root: Node2D = level.get_node("Buttons")
	var manager: PuzzleDoorManager = level.get_node("DoorManager")
	var sound_fields: Node2D = level.get_node("SoundFields")

	# 0. Resources: copied CCCAT door atlas + 2x2 button frames.
	var tileset: TileSet = door_tiles.tile_set
	check(tileset != null, "DoorTiles uses a tile set")
	if tileset != null:
		check(tileset.get_physics_layers_count() == 1, "Door tile set has one physics layer")
		check(tileset.get_physics_layer_collision_layer(0) == 1, "Door collision is on terrain layer 1")
		check(tileset.get_source_count() == 1, "Door tile set has one atlas source")
		var source := tileset.get_source(0) as TileSetAtlasSource
		check(source != null and source.texture != null and source.texture.get_size() == Vector2(128, 96),
			"Door atlas is the copied 128x96 CCCAT texture")
		check(tileset.get_terrain_name(0, 3) == "门", "Door terrain is named 门")
	check(DoorButton.atlas_coords_for(DoorButton.Mode.ONE_SHOT, false) == Vector2i(0, 0),
		"One-shot idle frame is top-left")
	check(DoorButton.atlas_coords_for(DoorButton.Mode.ONE_SHOT, true) == Vector2i(1, 0),
		"One-shot lit frame is top-right")
	check(DoorButton.atlas_coords_for(DoorButton.Mode.REBOUND, false) == Vector2i(0, 1),
		"Rebound idle frame is bottom-left")
	check(DoorButton.atlas_coords_for(DoorButton.Mode.REBOUND, true) == Vector2i(1, 1),
		"Rebound lit frame is bottom-right")

	# 1. Paint three door groups in Room1 and place their buttons.
	# 测试替换按钮前解除管理器缓存，避免物理帧访问已释放的旧按钮。
	manager.clear()
	door_tiles.clear()
	var door_cells: Array[Vector2i] = [
		Vector2i(20, 11), Vector2i(20, 12), Vector2i(20, 13),
		Vector2i(24, 11), Vector2i(24, 12),
		Vector2i(28, 11), Vector2i(28, 12),
	]
	for cell in door_cells:
		door_tiles.set_cell(cell, 0, Vector2i(3, 2))
	for child in buttons_root.get_children():
		child.queue_free()
	await frames(2)

	var button_a: DoorButton = load("res://scenes/world/button_rebound.tscn").instantiate()
	button_a.position = Vector2(232, 232)
	button_a.door_cells = _typed_cells(Vector2i(20, 11))
	buttons_root.add_child(button_a)

	var button_b: DoorButton = load("res://scenes/world/button_once.tscn").instantiate()
	button_b.position = Vector2(280, 232)
	button_b.door_cells = _typed_cells(Vector2i(24, 11))
	buttons_root.add_child(button_b)

	var button_c1: DoorButton = load("res://scenes/world/button_rebound.tscn").instantiate()
	button_c1.position = Vector2(344, 232)
	button_c1.door_cells = _typed_cells(Vector2i(28, 11))
	buttons_root.add_child(button_c1)

	var button_c2: DoorButton = load("res://scenes/world/button_rebound.tscn").instantiate()
	button_c2.position = Vector2(376, 232)
	button_c2.door_cells = _typed_cells(Vector2i(28, 11))
	buttons_root.add_child(button_c2)

	manager.setup(level.get_rooms())
	await frames(3)

	var door_a := manager.get_door_id_at_cell(Vector2i(20, 11))
	var door_b := manager.get_door_id_at_cell(Vector2i(24, 11))
	var door_c := manager.get_door_id_at_cell(Vector2i(28, 11))
	check(manager.get_door_count() == 3, "Door manager groups the painted cells into three doors")
	check(door_a >= 0 and door_b >= 0 and door_c >= 0, "Every painted door resolves to a door id")
	check(manager.get_door_cells(door_a).size() == 3 and manager.get_door_cells(door_c).size() == 2,
		"Door groups contain the painted cells")
	check(door_tiles.get_cell_source_id(Vector2i(20, 11)) != -1, "Closed door tiles are present")

	# 2. lv0 does not trigger.
	var f0 := _spawn_field(sound_fields, Vector2(232, 232), 48.0, 0)
	await frames(3)
	check(not button_a.is_pressed(), "lv0 field does not press a button")
	check(not manager.is_door_open(door_a), "lv0 field leaves the door closed")
	f0.queue_free()
	await frames(3)

	# 3. lv1 triggers a rebound button; the door closes when the field ends.
	var f1 := _spawn_field(sound_fields, Vector2(232, 232), 48.0, 1)
	await frames(3)
	check(button_a.is_pressed(), "lv1 field presses a button")
	check(manager.is_door_open(door_a), "Pressed button opens its door")
	check(door_tiles.get_cell_source_id(Vector2i(20, 11)) == -1, "Open door erases its tiles")
	check((button_a.get_node("Sprite2D") as Sprite2D).frame_coords == Vector2i(1, 1),
		"Pressed rebound button uses the lit bottom-right frame")
	f1.queue_free()
	await frames(3)
	check(not button_a.is_pressed(), "Rebound button releases when the field ends")
	check(not manager.is_door_open(door_a), "Rebound door closes when the field ends")
	check(door_tiles.get_cell_source_id(Vector2i(20, 11)) != -1, "Closed door restores its tiles")

	# 4. lv2 also triggers.
	var f2 := _spawn_field(sound_fields, Vector2(232, 232), 48.0, 2)
	await frames(3)
	check(button_a.is_pressed() and manager.is_door_open(door_a), "lv2 field also triggers the button")
	f2.queue_free()
	await frames(3)

	# 5. One-shot button latches.
	var fb := _spawn_field(sound_fields, Vector2(280, 232), 48.0, 1)
	await frames(3)
	check(button_b.is_pressed() and manager.is_door_open(door_b), "One-shot button opens its door")
	check((button_b.get_node("Sprite2D") as Sprite2D).frame_coords == Vector2i(1, 0),
		"Pressed one-shot button uses the lit top-right frame")
	fb.queue_free()
	await frames(3)
	check(button_b.is_latched() and button_b.is_pressed(), "One-shot button stays latched")
	check(manager.is_door_open(door_b), "One-shot door stays open")
	check(door_tiles.get_cell_source_id(Vector2i(24, 11)) == -1, "Latched door remains open")

	# 6. Two rebound buttons covered by one wave latch the whole group.
	var fc := _spawn_field(sound_fields, Vector2(360, 232), 96.0, 1)
	await frames(3)
	check(button_c1.is_pressed() and button_c2.is_pressed(), "One wave can press both group buttons")
	check(manager.is_door_open(door_c), "All group buttons open the door")
	check(button_c1.is_latched() and button_c2.is_latched(),
		"Simultaneously pressed rebound group latches")
	fc.queue_free()
	await frames(3)
	check(button_c1.is_pressed() and button_c2.is_pressed(), "Latched group stays pressed")
	check(manager.is_door_open(door_c), "Latched group keeps the door open")

	# 7. Room reset closes doors and clears latches.
	level.reset_to_checkpoint()
	await frames(3)
	check(not manager.is_door_open(door_c), "Room reset closes the latched door")
	check(door_tiles.get_cell_source_id(Vector2i(28, 11)) != -1, "Room reset restores door tiles")
	check(not button_b.is_latched() and not button_b.is_pressed(), "Room reset clears the one-shot latch")
	check(not button_c1.is_latched() and not button_c1.is_pressed(),
		"Room reset clears group latches")

	print("\nButton/door checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
