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

	var spikes: SpikeField = level.get_node_or_null("Spikes") as SpikeField
	check(spikes != null, "Big map has a Spikes TileMapLayer")
	if spikes == null:
		quit(1)
		return
	check(not spikes.visible, "Spike layer is hidden at runtime (editor-only marker)")

	var sound_fields: Node2D = level.get_node("SoundFields")
	var start_cell: Vector2i = spikes.local_to_map(spikes.to_local(level.player.global_position))
	var spike_cell := start_cell + Vector2i(3, 0)
	spikes.set_cell(spike_cell, 0, Vector2i.ZERO)
	spikes.refresh_baseline()
	var spike_world: Vector2 = spikes.to_global(spikes.map_to_local(spike_cell))

	# 测试专用：加快节奏、延长单场寿命，便于计数。
	spikes.cycle_interval = 0.05
	spikes.burst_interval = 0.05
	spikes.field_lifetime = 5.0

	# 刺声场会震碎 lv1 玻璃。
	var lv1: TileMapLayer = level.breakables.lv1
	var glass_cell: Vector2i = lv1.local_to_map(lv1.to_local(spike_world))
	level.breakables.paint_cell(1, glass_cell)
	level.breakables.refresh()
	check(level.breakables.has_cell(1, glass_cell), "Glass starts intact next to the spike")

	await frames(30)
	var pulse_side: float = spikes.field_side_cells * 16.0
	var pulses: Array = []
	for child in sound_fields.get_children():
		if child is SoundField and absf(child.side_length - pulse_side) < 0.01:
			pulses.append(child)
	check(pulses.size() >= 3, "Spike emits three pulse fields per burst")
	if not pulses.is_empty():
		var field: SoundField = pulses[0]
		check(absf(field.side_length - pulse_side) < 0.01,
			"Spike pulse side is field_side_cells × 16 (%.1f px)" % pulse_side)
		check(field.color.r > 0.9 and field.color.g < 0.4, "Spike pulse is red")
		check(not field.safe_for_player, "Spike pulse is not a player-safe zone")
		check(not field.lethal, "Spike pulse is visual only; kill uses the spike cell")
	check(level.breakables.has_cell(1, glass_cell), "Spike field is lv0 and leaves glass intact")

	# 停掉连发、清掉现有刺声场，再单独测试接触死亡。
	spikes.cycle_interval = 1000.0
	spikes._burst_left = 0
	spikes._cycle_elapsed = 0.0
	for child in sound_fields.get_children():
		if child is SoundField:
			child.queue_free()
	await frames(3)

	spikes.cycle_interval = 0.05
	spikes._cycle_elapsed = 0.0
	var deaths_before: int = level.deaths
	level.player.reset_to(spike_world)
	await frames(20)
	check(level.deaths > deaths_before, "Touching the spike cell kills the player")
	check(level.is_dead(), "Spike death waits for R before resetting")
	check(level.player.global_position.distance_to(level.get_checkpoint_anchor()) > 40.0,
		"Spike death does not respawn immediately")

	var death_fields: Array = []
	for child in sound_fields.get_children():
		if child is SoundField and not child.lethal and not child.safe_for_player \
				and absf(child.side_length - 80.0) < 0.01:
			death_fields.append(child)
	check(death_fields.size() >= 1, "Player death emits an 80 px field")
	if not death_fields.is_empty():
		var death_field: SoundField = death_fields[0]
		check(death_field.color.r > 0.9 and death_field.color.g < 0.4, "Death field is red")
		check(not death_field.safe_for_player, "Death field is only visual")

	level.reset_to_checkpoint()
	await frames(3)
	check(not level.is_dead(), "R clears the spike dead state")
	check(level.player.global_position.distance_to(level.get_checkpoint_anchor()) < 40.0,
		"R respawns the player at the checkpoint")

	spikes.cycle_interval = 1000.0
	spikes._burst_left = 0
	for child in sound_fields.get_children():
		if child is SoundField:
			child.queue_free()
	await frames(2)

	# lv1 不摧毁刺，lv2 摧毁；R 重置恢复。
	var lv1_side: float = level.player.landing_lv1_side_cells * 16.0
	level._on_wave(spike_world, lv1_side, 1, "landing")
	await frames(2)
	check(spikes.get_cell_source_id(spike_cell) != -1, "Level-1 field does not destroy the spike")

	var lv2_side: float = level.player.landing_lv2_side_cells * 16.0
	level._on_wave(spike_world, lv2_side, 2, "landing")
	await frames(2)
	check(spikes.get_cell_source_id(spike_cell) == -1, "Level-2 field destroys the spike")
	var lv2_field: SoundField = null
	for child in sound_fields.get_children():
		if child is SoundField and child.level == 2 and child.emitter == level.player:
			lv2_field = child
			break
	check(lv2_field != null and lv2_field.lifetime == SoundField.LV2_LIFETIME,
		"World level-2 wave lasts 2 seconds")

	level.reset_to_checkpoint()
	await frames(2)
	check(spikes.get_cell_source_id(spike_cell) != -1, "Room reset restores the spike")
	var lv2_after_reset := false
	for child in sound_fields.get_children():
		if child is SoundField and child.level == 2 and child.emitter == level.player:
			lv2_after_reset = true
	check(not lv2_after_reset, "Room reset clears the level-2 wave")

	level.breakables.clear_all()
	level.noise.clear_all()
	print("\nSpike checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
