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
	for _i in range(120):
		await physics_frame
		if level.player.is_on_floor():
			break

	var triggers: TriggerField = level.get_node_or_null("Triggers") as TriggerField
	check(triggers != null, "Big map has a Triggers TileMapLayer")
	if triggers == null:
		quit(1)
		return

	var sound_fields: Node2D = level.get_node("SoundFields")
	var trigger_cell: Vector2i = triggers.local_to_map(triggers.to_local(level.player.global_position))
	# 玩家可能贴边轻微滑动，铺 3×3 触发格保证测试期间始终踩在触发区上。
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			triggers.set_cell(trigger_cell + Vector2i(dx, dy), 1, Vector2i.ZERO)
	check(triggers.get_cell_source_id(trigger_cell) != -1, "Trigger cell is painted")

	# 触发方块不震碎玻璃。
	var lv1: TileMapLayer = level.breakables.lv1
	var glass_cell: Vector2i = lv1.local_to_map(lv1.to_local(level.player.global_position))
	level.breakables.paint_cell(1, glass_cell)
	level.breakables.refresh()

	# 测试专用：缩短冷却、延长单场寿命，便于计数。
	triggers.cooldown = 0.1
	triggers.field_lifetime = 2.0
	await frames(30)

	var fields: Array = []
	for child in sound_fields.get_children():
		if child is SoundField and not child.lethal and absf(child.side_length - 48.0) < 0.01:
			fields.append(child)
	check(fields.size() >= 2, "Standing on a trigger emits repeatedly (cooldown 0.1 s)")
	if not fields.is_empty():
		var field: SoundField = fields[0]
		check(field.color.r > 0.9 and field.color.g > 0.9 and field.color.b > 0.9, "Trigger field is white")
		check(field.safe_for_player, "Trigger field is a player-safe zone")
	check(level.breakables.has_cell(1, glass_cell), "Trigger field does not break glass")

	# 冷却：设为 10 秒后，首次触发一次，之后 0.25 秒内不再触发。
	for child in sound_fields.get_children():
		if child is SoundField:
			child.queue_free()
	await frames(2)
	triggers.cooldown = 10.0
	triggers._cooldown_remaining = 0.0
	await frames(5)
	var count_after_first := 0
	for child in sound_fields.get_children():
		if child is SoundField and not child.lethal:
			count_after_first += 1
	await frames(30)
	var count_later := 0
	for child in sound_fields.get_children():
		if child is SoundField and not child.lethal:
			count_later += 1
	check(count_after_first == 1 and count_later == 1, "Cooldown prevents immediate re-triggering")

	for child in sound_fields.get_children():
		if child is SoundField:
			child.queue_free()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			triggers.erase_cell(trigger_cell + Vector2i(dx, dy))
	level.breakables.clear_all()
	print("\nTrigger checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
