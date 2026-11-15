extends SceneTree
## 在用户的实际地图上检查参数覆盖、发射间隔和安全区域连续性。

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value:
		print("PASS  ", message)
	else:
		failures.append(message)
		push_error("FAIL  " + message)

func _run() -> void:
	var world: Node2D = load("res://scenes/world/big_map.tscn").instantiate()
	world.get_node("DoorManager").log_doors = false
	root.add_child(world)
	current_scene = world
	world.player.controls_enabled = false
	check(world._inside_active_sound_field(world.player.global_position),
		"Map load protects the spawn immediately, before the first physics frame")
	var reference: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	var matching := true
	var count := 0
	for node in world.get_node("Objects").get_children():
		if node is Checkpoint:
			count += 1
			matching = matching and is_equal_approx(node.field_interval, reference.idle_wave_interval) \
				and is_equal_approx(node.field_lifetime, reference.wave_lifetime)
	var reference_expansion := reference.wave_expand_duration
	reference.free()
	check(matching and count > 0, "All %d placed checkpoints match the animal interval and lifetime" % count)

	var cp: Checkpoint = world.get_node("Objects/Checkpoint4")
	world.player.reset_to(cp.respawn_position())
	for _i in 3:
		await physics_frame
	var last_id := 0
	var emissions: Array[int] = []
	var max_layers := 0
	var safe := true
	var longer_lived := false
	var expansion_matches := true
	for i in Engine.physics_ticks_per_second * 3:
		await physics_frame
		var layers := 0
		for node in world.sound_fields.get_children():
			if node is SoundField and not node.is_queued_for_deletion() and node.emitter == null \
					and node.safe_for_player and node.contains_point(cp.global_position):
				layers += 1
				if last_id != node.get_instance_id():
					last_id = node.get_instance_id()
					emissions.append(Engine.get_physics_frames())
				longer_lived = longer_lived or node.age > 0.7
				expansion_matches = expansion_matches and is_equal_approx(node.expand_duration, reference_expansion)
		max_layers = maxi(max_layers, layers)
		safe = safe and layers > 0 and not world.is_dead()
		if i == int(Engine.physics_ticks_per_second * 0.75) and "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/checkpoint-wave-fixed.png")
	var steady_interval := emissions.size() >= 3 and emissions.size() <= 4
	for i in range(1, emissions.size()):
		steady_interval = steady_interval and abs(emissions[i] - emissions[i - 1] - Engine.physics_ticks_per_second) <= 3
	check(steady_interval, "Actual map checkpoint emits once per second")
	check(max_layers == 1, "Actual map shows only one checkpoint wave at a time")
	check(longer_lived and expansion_matches, "Wave remains effective past 0.7 s and expands at the animal's speed")
	check(safe, "Player remains continuously protected through successive waves")
	# 不同发射相位下死亡重开：旧波被清掉后，复活同一帧必须已有新波。
	for phase: float in [0.05, 0.45, 0.95]:
		for _i in ceili(phase * Engine.physics_ticks_per_second):
			await physics_frame
		world._die()
		world.reset_to_checkpoint()
		world.player.controls_enabled = false
		check(world._inside_active_sound_field(world.player.global_position) and not world.is_dead(),
			"Respawn at phase %.2f s emits a protective wave synchronously" % phase)
		var survived := true
		for _i in ceili(1.1 * Engine.physics_ticks_per_second):
			await physics_frame
			survived = survived and not world.is_dead()
		check(survived, "Respawn at phase %.2f s stays safe until the next periodic wave" % phase)
	world._refresh_room(world.get_checkpoint_room())
	var refreshed := false
	for node in world.sound_fields.get_children():
		if node is SoundField and not node.is_queued_for_deletion() and node.emitter == null \
				and node.safe_for_player and node.contains_point(cp.global_position) and is_zero_approx(node.age):
			refreshed = true
	check(refreshed, "Refreshing the current room also emits its first wave immediately")
	world.queue_free()
	await process_frame
	print("\nCheckpoint wave checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
