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
	var map = load("res://scenes/world/big_map.tscn").instantiate()
	map.start_room = map.get_node("Rooms/Room1")
	var spikes: TileMapLayer = map.get_node("Spikes")
	spikes.clear()
	# 两组在 Room1：两格连在一起 + 单格；一组在 Room2。
	var cells: Array[Vector2i] = [
		Vector2i(12, 8), Vector2i(13, 8), Vector2i(20, 8), Vector2i(40, 8)
	]
	for cell in cells:
		spikes.set_cell(cell, 0, Vector2i.ZERO)
	level = map
	root.add_child(level)
	current_scene = level
	await frames(3)

	check(not spikes.visible, "Spike layer is hidden at runtime (editor-only marker)")
	var monsters_root := level.get_node_or_null("Monsters")
	check(monsters_root != null, "Spike groups spawn in a Monsters container")
	if monsters_root == null:
		quit(1)
		return
	var monsters: Array = monsters_root.get_children()
	check(monsters.size() == 3, "Each connected spike group becomes one monster")

	var pair_monster: Node2D = null
	var single_a: Node2D = null
	var single_b: Node2D = null
	for node in monsters:
		var monster := node as Node2D
		if monster == null:
			continue
		if absf(monster.global_position.x - 208.0) < 24.0:
			pair_monster = monster
		elif absf(monster.global_position.x - 328.0) < 24.0:
			single_a = monster
		else:
			single_b = monster
	check(pair_monster != null and single_a != null and single_b != null, "Monsters keep their group positions")
	if pair_monster == null or single_a == null or single_b == null:
		quit(1)
		return
	check(pair_monster.get_child_count() == 2, "A two-cell spike group becomes one two-cell monster")
	for monster in monsters:
		monster.visual_cycle_interval = 0.05
		monster.visual_burst_interval = 0.05
		monster.visual_lifetime = 5.0
	await frames(30)
	var field_root: Node2D = level.get_node("SoundFields")
	var red_pulses := 0
	for child in field_root.get_children():
		if child is SoundField and child.level == 0 and not child.safe_for_player \
				and absf(child.side_length - 48.0) < 0.01:
			red_pulses += 1
	check(red_pulses >= 3, "Monsters emit the triple red visual pulses")
	var hitbox_ok := true
	for child in pair_monster.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			if (child.shape as RectangleShape2D).size != Vector2(16, 16):
				hitbox_ok = false
	check(hitbox_ok, "Monster hitbox remains one 16x16 shape per cell")
	for child in field_root.get_children():
		if child is SoundField and child.level == 0 and not child.safe_for_player \
				and absf(child.side_length - 48.0) < 0.01:
			child.queue_free()
	for monster in monsters:
		monster.visual_cycle_interval = 1000.0
		monster.visual_burst_count = 0
		monster._burst_left = 0
	await frames(3)
	var pair_home: Vector2 = pair_monster.global_position
	var single_home: Vector2 = single_a.global_position

	# 1. 无重力：玩家静止、无动物时怪不会下坠/移动。
	await frames(30)
	check(pair_monster.global_position.distance_to(pair_home) < 0.5,
		"Monsters ignore gravity and stay put without a target")

	# 2. 追击动物。
	var animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(animal)
	animal.global_position = pair_monster.global_position + Vector2(64, 0)
	await frames(2)
	var animal_dir := (animal.global_position - pair_monster.global_position).normalized()
	var chase_start := pair_monster.global_position
	await frames(20)
	var chase_moved := pair_monster.global_position - chase_start
	check(chase_moved.length() > 2.0 and chase_moved.dot(animal_dir) > 0.0,
		"Monster chases an animal in its room")
	animal.queue_free()
	await frames(5)

	# 3. 追击移动中的玩家；玩家停下后怪也停下。
	level.player.reset_to(level.get_checkpoint_anchor())
	await frames(3)
	var player_start: Vector2 = pair_monster.global_position
	var dir_to_player: Vector2 = (level.player.global_position - player_start).normalized()
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	var player_moved: Vector2 = pair_monster.global_position - player_start
	check(player_moved.length() > 2.0 and player_moved.dot(dir_to_player) > 0.0,
		"Monster chases the moving player")
	await frames(30)
	var stopped_pos := pair_monster.global_position
	await frames(20)
	check(pair_monster.global_position.distance_to(stopped_pos) < 0.5,
		"Monster stops when the player stops moving")

	# 4. 离谁近追谁：左侧动物比右侧移动玩家更近，怪应向左。
	var nearby: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(nearby)
	nearby.global_position = pair_monster.global_position + Vector2(-48, 0)
	await frames(2)
	var nearest_start := pair_monster.global_position
	Input.action_press("move_right")
	await frames(15)
	Input.action_release("move_right")
	check(pair_monster.global_position.x < nearest_start.x - 1.0,
		"Monster chases the nearest sound source")
	nearby.queue_free()
	await frames(5)

	# 5. 不跨房间：手动激活 Room2 的怪，它不应追 Room1 的玩家。
	level.player.reset_to(level.get_checkpoint_anchor())
	await frames(3)
	single_b.process_mode = Node.PROCESS_MODE_INHERIT
	var cross_start := single_b.global_position
	await frames(30)
	check(single_b.global_position.distance_to(cross_start) < 0.5,
		"Monster does not chase across rooms")

	# 6. lv1 波把怪推走。
	level.reset_to_checkpoint()
	await frames(3)
	var push_start := pair_monster.global_position
	var lv1_side: float = level.player.landing_lv1_side_cells * 16.0
	level._on_wave(pair_monster.global_position, lv1_side, 1, "landing")
	await frames(8)
	check(pair_monster.global_position.distance_to(push_start) > 3.0,
		"Level-1 wave pushes the monster away")

	# 7. lv2 波把怪定住（不推走）。
	level.reset_to_checkpoint()
	await frames(3)
	var bait: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(bait)
	bait.global_position = single_a.global_position + Vector2(48, 0)
	await frames(2)
	var lv2_side: float = level.player.landing_lv2_side_cells * 16.0
	level._on_wave(single_a.global_position, lv2_side, 2, "landing")
	await frames(2)
	var frozen_star: Vector2 = single_a.global_position
	await frames(30)
	check(single_a.global_position.distance_to(frozen_star) < 0.5,
		"Level-2 wave freezes the monster without pushing it")
	bait.queue_free()
	await frames(3)

	# 7b. 非玩家声场（例如动物蓝色场）不会推/冻刺怪。
	level.reset_to_checkpoint()
	await frames(3)
	var sound_fields: Node2D = level.get_node("SoundFields")
	var decoy_emitter := Node2D.new()
	level.add_child(decoy_emitter)
	var decoy_field := SoundField.new()
	decoy_field.side_length = 96.0
	decoy_field.lifetime = 2.0
	decoy_field.level = 1
	decoy_field.emitter = decoy_emitter
	sound_fields.add_child(decoy_field)
	decoy_field.global_position = single_a.global_position
	var decoy_start: Vector2 = single_a.global_position
	await frames(10)
	check(single_a.global_position.distance_to(decoy_start) < 0.5,
		"Non-player sound fields do not push monsters")
	decoy_field.queue_free()
	decoy_emitter.queue_free()
	await frames(3)

	# 8. R 重置让怪回到出生位置。
	pair_monster.global_position = pair_home + Vector2(40, 0)
	single_a.global_position = single_home + Vector2(0, 40)
	level.reset_to_checkpoint()
	await frames(3)
	check(pair_monster.global_position.distance_to(pair_home) < 0.5
		and single_a.global_position.distance_to(single_home) < 0.5,
		"R reset returns monsters to their home positions")

	# 9. 接触玩家 → 死亡；接触动物 → 吃掉。
	level.player.reset_to(pair_monster.global_position)
	await frames(3)
	check(level.is_dead(), "Touching a monster kills the player")
	level.reset_to_checkpoint()
	await frames(3)
	var prey: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	level.add_child(prey)
	prey.global_position = single_a.global_position
	await frames(3)
	check(not prey.is_alive() and not prey.visible, "Monster eats an animal it touches")
	level.reset_to_checkpoint()
	await frames(3)
	check(prey.is_alive(), "R revives an eaten animal")

	level.breakables.clear_all()
	level.noise.clear_all()
	print("\nSpike checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
