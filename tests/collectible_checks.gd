extends SceneTree

var level: Node2D
var failures: Array[String] = []
var collected_count := 0

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

func _on_collected(_collectible: Node) -> void:
	collected_count += 1

func _spawn_star(world_position: Vector2) -> Area2D:
	var star := load("res://scenes/world/collectible.tscn").instantiate() as Area2D
	level.get_node("Collectibles").add_child(star)
	star.global_position = world_position
	return star

func _run() -> void:
	level = load("res://scenes/world/big_map.tscn").instantiate()
	level.get_node("Spikes").clear()
	level.start_room = level.get_node("Rooms/Room1")
	root.add_child(level)
	current_scene = level
	await frames(2)

	# 1. 贴图与缓慢旋转。
	var star := _spawn_star(level.player.global_position + Vector2(48, 0))
	await frames(2)
	var sprite: Sprite2D = star.get_node("Sprite2D") as Sprite2D
	check(sprite != null and sprite.texture != null, "Collectible uses the star sprite")
	var rotation_before: float = sprite.rotation
	await frames(10)
	check(absf(sprite.rotation - rotation_before) > 0.01, "Collectible sprite rotates slowly")
	check(star.collision_layer == 0 and star.collision_mask == 2,
		"Collectible only detects the player and is not solid")
	check(not star.monitorable, "Collectible is not monitorable by other areas")

	# 2. 玩家接触即收集，且不会被挡住。
	var star_position: Vector2 = star.global_position
	star.connect("collected", _on_collected)
	level.player.reset_to(star_position)
	await frames(3)
	check(collected_count == 1, "Player collects the star on contact")
	check(not is_instance_valid(star) or star.is_queued_for_deletion(), "Collected star disappears")
	check(level.player.global_position.distance_to(star_position) < 1.0,
		"Collectible does not physically block the player")

	# 3. 房间裁剪：当前房间保留，远处房间禁用但节点不释放。
	var far_star := _spawn_star(level.get_node("Rooms/Room7").get_rect().get_center())
	var near_star := _spawn_star(level.player.global_position + Vector2(32, 0))
	await frames(1)
	level._update_room_culling(true)
	await frames(2)
	check(far_star.process_mode == Node.PROCESS_MODE_DISABLED and not far_star.is_visible_in_tree(),
		"Collectible in a far room is culled")
	check(near_star.process_mode != Node.PROCESS_MODE_DISABLED and near_star.is_visible_in_tree(),
		"Collectible in the player's room stays active")
	check(is_instance_valid(far_star), "Culled collectible is not freed")

	print("\nCollectible checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
