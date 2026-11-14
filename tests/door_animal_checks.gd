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

func _press_restart() -> void:
	var event := InputEventAction.new()
	event.action = &"restart"
	event.pressed = true
	level._unhandled_input(event)

func _run() -> void:
	await _test_door()
	await _test_animal()
	print("\nDoor/animal checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_door() -> void:
	level = load("res://scenes/world/big_map.tscn").instantiate()
	# 本套件不测试刺怪，清空刺格避免地图里的怪干扰门测试。
	level.get_node("Spikes").clear()
	root.add_child(level)
	current_scene = level
	await frames(2)
	# 地图里游荡的动物会撞上门陷阱，干扰门测试；先清掉。
	for animal in level.get_node("Animals").get_children():
		animal.queue_free()
	await frames(2)

	var rooms: Array[Room] = level.get_rooms()
	var checkpoint_room: Room = level.get_checkpoint_room()
	var room2: Room = rooms[0]
	for room in rooms:
		if room != checkpoint_room:
			room2 = room
			break
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
	_press_restart()
	await frames(3)
	door.restore()
	await frames(2)
	check(not door._consumed and door.visible and door._aura != null, "Door restores with its pulse field")

	var door2: Door = load("res://scenes/world/door.tscn").instantiate()
	door2.global_position = level.player.global_position + Vector2(64, 0)
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
	_press_restart()
	await frames(3)
	check(not door2._consumed and door2.visible, "R reset restores the door in the checkpoint room")

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
	var animal_sprite: Sprite2D = animal.get_node_or_null("Sprite2D")
	check(animal_sprite != null and animal_sprite.texture != null and animal.visible,
		"Animal has a visible sprite")

	var sound_fields: Node2D = level.get_node("SoundFields")
	animal.idle_wave_interval = 0.1
	await frames(20)
	var idle_side: float = animal.idle_wave_side_cells * 16.0
	var idle_field: SoundField = null
	for child in sound_fields.get_children():
		if child is SoundField and child.emitter == animal and child.level == 1 \
				and absf(child.side_length - idle_side) < 0.01:
			idle_field = child
			break
	check(idle_field != null, "Idle animal emits its configured blue (lv1) sound field")
	check(idle_field != null and idle_field.color.b > idle_field.color.r
		and idle_field.color.b > idle_field.color.g, "Animal sound field is blue")

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
		if child is SoundField and child.emitter == animal 				and absf(child.side_length - animal.move_wave_side_cells * 16.0) < 0.01:
			moving_field = child
			break
	check(moving_field != null, "Animal emits its configured move sound fields while moving")
	if moving_field != null:
		check(absf(moving_field.lifetime - animal.wave_lifetime) < 0.01
			and absf(moving_field.expand_duration - animal.wave_expand_duration) < 0.01,
			"Animal fields last longer and expand slower")

	animal.idle_wave_interval = 5.0
	lv1.queue_free()
	await frames(120)
	var x1: float = animal.global_position.x
	await frames(20)
	check(absf(animal.global_position.x - x1) < 0.1, "Animal stops after completing its finite blue-triggered travel")
	var stop_idle_found := false
	for child in sound_fields.get_children():
		if child is SoundField and child.emitter == animal and child.level == 1 \
				and absf(child.side_length - animal.idle_wave_side_cells * 16.0) < 0.01:
			stop_idle_found = true
			break
	check(stop_idle_found, "Stopping emits the idle sound field immediately")

	# lv2 震飞：动物被击飞一段距离后受重力落地。
	var knock_x: float = animal.global_position.x
	var knock := SoundField.new()
	knock.side_length = 160.0
	knock.lifetime = 2.0
	knock.level = 2
	knock.safe_for_player = true
	sound_fields.add_child(knock)
	knock.global_position = animal.global_position
	await frames(8)
	check(animal.global_position.x > knock_x + 10.0, "lv2 field knocks the animal away")
	check(animal.velocity.y < 0.0 or not animal.is_on_floor(), "Knocked animal leaves the ground")
	knock.queue_free()
	await frames(80)
	check(animal.is_on_floor(), "Knocked animal falls back to the floor")

	# R / 重启时动物归位。
	var home_position: Vector2 = animal._home_position
	level.restart_run()
	await frames(2)
	check(animal.global_position.distance_to(home_position) < 0.5,
		"Restart returns the animal to its home position")

	# 守边：临时平台 + 左侧 lv1 声场，动物停在平台右缘而不掉落。
	var edge_animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(edge_animal)
	edge_animal.global_position = Vector2(700, 284)
	var edge_platform := StaticBody2D.new()
	edge_platform.collision_layer = 1
	edge_platform.collision_mask = 0
	var edge_shape := CollisionShape2D.new()
	var edge_rect := RectangleShape2D.new()
	edge_rect.size = Vector2(96, 16)
	edge_shape.shape = edge_rect
	edge_platform.add_child(edge_shape)
	level.add_child(edge_platform)
	edge_platform.global_position = Vector2(700, 300)
	await frames(4)
	var edge_field := SoundField.new()
	edge_field.side_length = 96.0
	edge_field.lifetime = 3.0
	edge_field.level = 1
	edge_field.safe_for_player = true
	sound_fields.add_child(edge_field)
	edge_field.global_position = Vector2(650, 284)
	await frames(70)
	check(edge_animal.global_position.x <= 749.0 and edge_animal.global_position.y < 300.0
		and edge_animal.is_on_floor(), "Animal stops at the platform edge instead of falling")
	edge_field.queue_free()
	edge_animal.queue_free()
	edge_platform.queue_free()
	await frames(3)

	# 一格深沟：主平台 + 低一格平台，动物会走下去继续前进。
	var pit_animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(pit_animal)
	pit_animal.global_position = Vector2(600, 284)
	var pit_main := StaticBody2D.new()
	pit_main.collision_layer = 1
	pit_main.collision_mask = 0
	var pit_main_shape := CollisionShape2D.new()
	var pit_main_rect := RectangleShape2D.new()
	pit_main_rect.size = Vector2(96, 16)
	pit_main_shape.shape = pit_main_rect
	pit_main.add_child(pit_main_shape)
	level.add_child(pit_main)
	pit_main.global_position = Vector2(600, 300)
	var pit_lower := StaticBody2D.new()
	pit_lower.collision_layer = 1
	pit_lower.collision_mask = 0
	var pit_lower_shape := CollisionShape2D.new()
	var pit_lower_rect := RectangleShape2D.new()
	pit_lower_rect.size = Vector2(96, 16)
	pit_lower_shape.shape = pit_lower_rect
	pit_lower.add_child(pit_lower_shape)
	level.add_child(pit_lower)
	pit_lower.global_position = Vector2(688, 316)
	await frames(4)
	var pit_field := SoundField.new()
	pit_field.side_length = 96.0
	pit_field.lifetime = 3.0
	pit_field.level = 1
	pit_field.emitter = level.player
	pit_field.safe_for_player = true
	sound_fields.add_child(pit_field)
	pit_field.global_position = Vector2(560, 284)
	await frames(90)
	check(pit_animal.global_position.x > 660.0 and pit_animal.global_position.y >= 296.0,
		"Animal walks across a one-tile-deep gap")
	pit_field.queue_free()
	pit_animal.queue_free()
	pit_main.queue_free()
	pit_lower.queue_free()
	await frames(3)

	# 爬一格：平台上放一个 16px 高的台阶，动物会被 lv1 声场驱赶着爬上去。
	var step_animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(step_animal)
	step_animal.global_position = Vector2(690, 284)
	var step_platform := StaticBody2D.new()
	step_platform.collision_layer = 1
	step_platform.collision_mask = 0
	var step_pshape := CollisionShape2D.new()
	var step_prect := RectangleShape2D.new()
	step_prect.size = Vector2(96, 16)
	step_pshape.shape = step_prect
	step_platform.add_child(step_pshape)
	level.add_child(step_platform)
	step_platform.global_position = Vector2(700, 300)
	var step := StaticBody2D.new()
	step.collision_layer = 1
	step.collision_mask = 0
	var step_shape := CollisionShape2D.new()
	var step_rect := RectangleShape2D.new()
	step_rect.size = Vector2(32, 16)
	step_shape.shape = step_rect
	step.add_child(step_shape)
	level.add_child(step)
	step.global_position = Vector2(724, 284)
	await frames(4)
	var step_field := SoundField.new()
	step_field.side_length = 96.0
	step_field.lifetime = 3.0
	step_field.level = 1
	step_field.safe_for_player = true
	sound_fields.add_child(step_field)
	step_field.global_position = Vector2(640, 284)
	await frames(90)
	check(step_animal.global_position.y <= 272.0 and step_animal.global_position.x > 708.0,
		"Animal climbs a one-tile step and keeps moving")
	step_field.queue_free()
	step_animal.queue_free()
	step_platform.queue_free()
	step.queue_free()
	await frames(3)

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
	check(not animal.is_alive() and not animal.visible, "Door eats the animal")
	check(door._consumed, "Door is consumed after eating the animal")

	level.queue_free()
	await frames(2)
