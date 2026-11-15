extends SceneTree
## 在实际地图上检查存档点「玩家激活后发出一次并保持」的安全声场、重置与房间切换。

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value:
		print("PASS  ", message)
	else:
		failures.append(message)
		push_error("FAIL  " + message)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _run() -> void:
	var world: Node2D = load("res://scenes/world/big_map.tscn").instantiate()
	world.get_node("DoorManager").log_doors = false
	root.add_child(world)
	current_scene = world
	world.player.controls_enabled = false

	var start_room: Room = world.room_at(world.player.global_position)
	check(start_room != null, "Player starts inside a room")
	# 选一个起始房间之外的存档点：未激活时不应有场。
	var cp: Checkpoint = null
	for node in world.get_node("Objects").get_children():
		var candidate := node as Checkpoint
		if candidate != null and world.room_at(candidate.global_position) != start_room:
			cp = candidate
			break
	check(cp != null, "Another room has a checkpoint")
	if cp == null:
		world.queue_free()
		await process_frame
		quit(1)
		return
	check(not cp.is_active() and _field_at(world, cp.respawn_position()) == null,
		"Unactivated checkpoint has no safe field")

	# 玩家接触激活：发出一次并保持。
	world.player.reset_to(cp.respawn_position())
	await frames(3)
	check(cp.is_active(), "Touching activates the checkpoint")
	var field: SoundField = _field_at(world, cp.respawn_position())
	check(field != null, "Activated checkpoint emits a safe field")
	if field != null:
		check(field.safe_for_player and not field.lethal and field.level == 0 and field.emitter == null,
			"Checkpoint field is a lv0 safe field with no emitter")
		check(absf(field.side_length - 80.0) < 0.01 and is_equal_approx(field.expand_duration, 0.5),
			"Checkpoint field is 5 cells and expands in 0.5 s")
		check(field.persistent and is_inf(field.lifetime), "Checkpoint field is persistent")
		check(field.contains_point(cp.respawn_position()), "Field covers the checkpoint respawn point")
	check(_count_fields_at(world, cp.respawn_position()) == 1,
		"Activated checkpoint has exactly one field")

	var field_id: int = field.get_instance_id() if field != null else 0
	var safe := true
	for _i in Engine.physics_ticks_per_second * 3:
		await physics_frame
		safe = safe and world._inside_active_sound_field(cp.respawn_position()) and not world.is_dead()
	check(is_instance_valid(field) and not field.is_queued_for_deletion() \
		and field.get_instance_id() == field_id,
		"Checkpoint field persists instead of pulsing")
	check(safe, "Checkpoint area stays safe for three seconds")

	world._restart_checkpoint_waves()
	check(_count_fields_at(world, cp.respawn_position()) == 1,
		"Restarting waves does not duplicate the field")

	for phase: float in [0.05, 0.45, 0.95]:
		for _i in ceili(phase * Engine.physics_ticks_per_second):
			await physics_frame
		world._die()
		world.reset_to_checkpoint()
		world.player.controls_enabled = false
		check(world._inside_active_sound_field(world.player.global_position) and not world.is_dead(),
			"Respawn at phase %.2f s is protected synchronously" % phase)
		var survived := true
		for _i in ceili(1.1 * Engine.physics_ticks_per_second):
			await physics_frame
			survived = survived and not world.is_dead()
		check(survived, "Respawn at phase %.2f s stays safe" % phase)

	# fields_enabled 关闭时主动清场，恢复后重建。
	cp.fields_enabled = false
	await frames(3)
	check(_field_at(world, cp.respawn_position()) == null,
		"Disabling checkpoint fields clears the safe field")
	cp.fields_enabled = true
	await frames(3)
	check(_field_at(world, cp.respawn_position()) != null,
		"Re-enabling checkpoint fields recreates the safe field")

	# 激活后离开房间组：声场保持不删除。
	var cp_room: Room = world.room_at(cp.global_position)
	var away: Room = world.get_node("Rooms/Room2")
	if away == cp_room:
		away = world.get_node("Rooms/Room1")
	world.player.reset_to(away.get_rect().get_center())
	await frames(3)
	check(cp.process_mode == Node.PROCESS_MODE_DISABLED \
		and _field_at(world, cp.respawn_position()) != null,
		"Leaving the room keeps the activated checkpoint field")
	world.player.reset_to(cp_room.get_rect().get_center())
	await frames(3)
	check(cp.process_mode != Node.PROCESS_MODE_DISABLED \
		and _count_fields_at(world, cp.respawn_position()) == 1,
		"Returning keeps exactly one field")

	world.queue_free()
	await process_frame
	print("\nCheckpoint wave checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _field_at(world: Node, point: Vector2) -> SoundField:
	for node in world.sound_fields.get_children():
		if node is SoundField and not node.is_queued_for_deletion() and node.emitter == null \
				and node.safe_for_player and node.contains_point(point):
			return node
	return null

func _count_fields_at(world: Node, point: Vector2) -> int:
	var count := 0
	for node in world.sound_fields.get_children():
		if node is SoundField and not node.is_queued_for_deletion() and node.emitter == null \
				and node.safe_for_player and node.contains_point(point):
			count += 1
	return count
