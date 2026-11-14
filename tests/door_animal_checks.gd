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
	await _test_door()
	await _test_animal()
	print("\nDoor/animal checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_door() -> void:
	level = load("res://scenes/world/big_map.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(2)

	var rooms: Array[Room] = level.get_rooms()
	var room2: Room = rooms[1] if rooms.size() > 1 else rooms[0]
	var door: Door = load("res://scenes/world/door.tscn").instantiate()
	door.global_position = room2.get_rect().get_center()
	level.add_child(door)
	await frames(2)

	var aura: DoorField = door._aura
	check(aura != null, "Door spawns its red pulse field")
	if aura != null:
		var lo := 9999.0
		var hi := 0.0
		for _i in range(200):
			await physics_frame
			lo = minf(lo, aura.side_length)
			hi = maxf(hi, aura.side_length)
		check(lo <= 18.0 and hi >= 46.0, "Door field pulses between 16 and 48 px")

	var sound_fields: Node2D = level.get_node("SoundFields")
	var white := SoundField.new()
	white.side_length = 48.0
	white.lifetime = 5.0
	white.emitter = level.player
	sound_fields.add_child(white)
	white.global_position = door.global_position
	var deaths_before: int = level.deaths
	await frames(4)
	check(level.deaths > deaths_before, "Door eats the owner of a white field it touches")
	check(door._consumed and not door.visible, "Consumed door is hidden")
	door.restore()
	await frames(2)
	check(not door._consumed and door.visible and door._aura != null, "Door restores with its pulse field")

	var checkpoint_room: Room = level.get_checkpoint_room()
	var door2: Door = load("res://scenes/world/door.tscn").instantiate()
	door2.global_position = checkpoint_room.get_rect().get_center()
	level.add_child(door2)
	await frames(2)
	var white2 := SoundField.new()
	white2.side_length = 48.0
	white2.lifetime = 5.0
	white2.emitter = level.player
	sound_fields.add_child(white2)
	white2.global_position = door2.global_position
	deaths_before = level.deaths
	await frames(4)
	check(level.deaths > deaths_before, "Door in the checkpoint room eats the player")
	check(not door2._consumed and door2.visible, "Room reset restores the door")

	var body_before: int = level.deaths
	level.player.reset_to(door2.global_position)
	await frames(4)
	check(level.deaths > body_before, "Door body contact eats the player")

	level.queue_free()
	await frames(2)

func _test_animal() -> void:
	level = load("res://scenes/levels/wave_jump_lab.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for _i in range(120):
		await physics_frame
		if level.player.is_on_floor():
			break
	level.noise.clear_all()
	level.breakables.clear_all()

	var animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(animal)
	animal.global_position = level.player.global_position + Vector2(48, -64)
	await frames(60)
	check(animal.is_on_floor(), "Animal is affected by gravity and lands")
	await frames(5)
	check(not animal.visible, "Animal has no visible texture")

	var sound_fields: Node2D = level.get_node("SoundFields")
	animal.idle_wave_interval = 0.1
	await frames(20)
	var idle_side: float = animal.idle_wave_side_cells * 16.0
	var idle_found := false
	for child in sound_fields.get_children():
		if child is SoundField and child.emitter == animal and child.level == 0 				and absf(child.side_length - idle_side) < 0.01:
			idle_found = true
	check(idle_found, "Idle animal emits its configured lv0 sound field")

	var lv1 := SoundField.new()
	lv1.side_length = 80.0
	lv1.lifetime = 2.0
	lv1.level = 1
	lv1.emitter = level.player
	sound_fields.add_child(lv1)
	lv1.global_position = animal.global_position + Vector2(-40, 0)
	var x0: float = animal.global_position.x
	await frames(30)
	check(animal.global_position.x > x0 + 10.0, "Animal moves away from an lv1 field")

	var moving_field: SoundField = null
	for child in sound_fields.get_children():
		if child is SoundField and child.emitter == animal 				and absf(child.side_length - animal.wave_side) < 0.01:
			moving_field = child
			break
	check(moving_field != null, "Animal emits its configured move sound fields while moving")
	if moving_field != null:
		check(absf(moving_field.lifetime - animal.wave_lifetime) < 0.01
			and absf(moving_field.expand_duration - animal.wave_expand_duration) < 0.01,
			"Animal fields last longer and expand slower")

	lv1.queue_free()
	await frames(40)
	var x1: float = animal.global_position.x
	await frames(20)
	check(absf(animal.global_position.x - x1) < 8.0, "Animal stops when the lv1 field ends")

	var door: Door = load("res://scenes/world/door.tscn").instantiate()
	door.global_position = animal.global_position + Vector2(64, 0)
	level.add_child(door)
	await frames(2)
	if is_instance_valid(animal) and not animal.is_queued_for_deletion():
		var bait := SoundField.new()
		bait.side_length = 48.0
		bait.lifetime = 5.0
		bait.emitter = animal
		sound_fields.add_child(bait)
		bait.global_position = door.global_position
		await frames(4)
	check(not is_instance_valid(animal) or animal.is_queued_for_deletion(), "Door eats the animal")
	check(door._consumed, "Door is consumed after eating the animal")

	level.queue_free()
	await frames(2)
