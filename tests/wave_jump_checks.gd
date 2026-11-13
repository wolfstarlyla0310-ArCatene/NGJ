extends SceneTree

const PULSE_SCRIPT := preload("res://scripts/force_pulse.gd")
var level: Node2D
var failures: Array[String] = []
var impulses: Array[Dictionary] = []
var impacts: Array[Vector2] = []

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

func record_impulse(force: Vector2, source: String) -> void:
	impulses.append({"force": force, "source": source})

func record_impact(_origin: Vector2, normal: Vector2, _strength: float) -> void:
	impacts.append(normal)

func make_pulse(origin: Vector2, radius: float = 240.0) -> Node2D:
	var pulse := Node2D.new()
	pulse.set_script(PULSE_SCRIPT)
	pulse.position = origin
	pulse.target = level.player
	pulse.max_radius = radius
	level.pulses.add_child(pulse)
	return pulse

func _run() -> void:
	level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(3)
	level.player.impulse_received.connect(record_impulse)
	level.player.wall_impact.connect(record_impact)
	level.restart_run()
	await frames(10)
	check(not level.player.direct_jump_enabled, "Ordinary jump starts disabled, as requested in reference")
	var ground_y: float = level.player.position.y
	Input.action_press("jump")
	await frames(18)
	Input.action_release("jump")
	check(absf(level.player.position.y - ground_y) < 1.0, "Space alone cannot launch player in wave mode")
	var wave: Node2D = level.fire_pulse()
	check(wave != null and level.fire_pulse() == null, "Left-click pulse has a finite range and a recharge interval")
	await frames(24)
	check(wave.has_hit and level.player.velocity.y < -300.0, "Wave from below launches player upward")
	check(level.player.position.y < ground_y - 35.0 and not level.player.is_on_floor(), "Wave jump really leaves the ground")
	check(level.wave_jumps == 1, "HUD counts an actual sound-powered takeoff")
	var peak_y: float = level.player.position.y
	for _i in range(240):
		await physics_frame
		peak_y = minf(peak_y, level.player.position.y)
	check(ground_y - peak_y > 130.0, "Wave jump clears a 128-pixel step height")
	await frames(90)
	check(level.player.is_on_floor(), "Player returns to a stable landing after wave jump")

	level.player.controls_enabled = false
	level.eye.input_enabled = false
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		level.player.reset_to(Vector2(480, 240))
		make_pulse(level.player.position - direction * 80.0)
		await frames(18)
		check(level.player.velocity.dot(direction) > 500.0, "Wave applies outward push in direction " + str(direction))
	level.player.reset_to(Vector2(480, 240))
	var count_before := impulses.size()
	make_pulse(Vector2(900, 240))
	await frames(85)
	check(impulses.size() == count_before and level.player.velocity.is_zero_approx(), "Player beyond wave radius receives no impulse")
	level.player.reset_to(Vector2(480, 240))
	count_before = impulses.size()
	make_pulse(Vector2(480, 320))
	await frames(65)
	check(impulses.size() == count_before + 1, "A pulse cannot apply force more than once to the same player")

	level.restart_run()
	level.player.reset_to(Vector2(180, 520))
	await frames(8)
	Input.action_press("move_left")
	await frames(50)
	Input.action_release("move_left")
	check(not impacts.is_empty() and impacts.back().x > 0.7, "Running into left wall produces a rightward reaction")
	check(level.player.position.x >= 140.0 - 0.1, "Wall reaction preserves solid collision boundaries")

	# Play the first elevated landing with actual wave propagation and normal horizontal input.
	level.restart_run()
	level.player.reset_to(Vector2(460, 522))
	level.eye.reset_to(Vector2(460, 576), level.get_node("Terrain/Floor"))
	await frames(10)
	level.fire_pulse()
	await frames(14)
	Input.action_press("move_right")
	await frames(70)
	Input.action_release("move_right")
	await frames(24)
	if not (level.player.is_on_floor() and level.player.position.y < 400.0):
		print("Ledge diagnostic: player=", level.player.position, " velocity=", level.player.velocity)
	check(level.player.is_on_floor() and level.player.position.y < 400.0 and level.player.position.x > 550.0, "Wave jump plus A/D reaches and lands on first ledge")

	# From the first ledge, another wave should reach the high platform.
	level.eye.reset_to(Vector2(level.player.position.x, 448), level.get_node("Terrain/LowLedge"))
	check(level.eye.can_occupy(level.eye.position), "Second jump source is genuinely inside the ledge")
	level.fire_pulse()
	await frames(14)
	Input.action_press("move_right")
	await frames(95)
	Input.action_release("move_right")
	await frames(24)
	if not (level.player.is_on_floor() and level.player.position.y < 280.0):
		print("High platform diagnostic: player=", level.player.position, " velocity=", level.player.velocity)
	check(level.player.is_on_floor() and level.player.position.y < 280.0 and level.player.position.x >= 748.0, "A second sound-powered jump reaches the high platform")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("\nWave jump checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
