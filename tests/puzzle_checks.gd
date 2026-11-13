extends SceneTree

var failures: Array[String] = []
var level: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if value:
		print("PASS  ", description)
	else:
		failures.append(description)
		push_error("FAIL  " + description)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func mouse_step(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	root.push_input(motion, true)

func mouse_click() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)

func walk_to(target_x: float) -> void:
	var action := "move_right" if target_x > level.player.position.x else "move_left"
	Input.action_press(action)
	var timeout := 600
	while absf(level.player.position.x - target_x) > 10.0 and timeout > 0 and level.active:
		timeout -= 1
		await physics_frame
	Input.action_release(action)
	await frames(12)

func _run() -> void:
	level = load("res://scenes/levels/l_relay_puzzle.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(4)
	check(level.player.show_body_in_eye and level.vision.get_shader_parameter("debug_visible"), "Map and player are visible with vision mechanic disabled")
	check(not level._gate_one_open and not level._gate_two_open, "Both pressure-controlled passages start disconnected")
	level.restart_run()
	level.eye.move_within_walls(Vector2(2000, 0))
	check(level.eye.position.x < 950.0, "Mouse cannot reach right wall before plate one is pressed")
	level.eye.reset_to(Vector2(288, 544), level.get_node("Terrain/Floor"))
	level.get_node("Camera2D").position.x = 4000.0
	await frames(4)
	check(level.active and level.phase == level.Phase.APPROACH, "Moving locator outside camera no longer causes death")
	level.get_node("Camera2D").position.x = 640.0
	await walk_to(816.0)
	check(level.plate_one.pressed and level._gate_one_open, "Real player contact on first pressure plate opens right-wall passage")
	for _i in range(67):
		mouse_step(Vector2(12, 0))
		await physics_frame
	for _i in range(13):
		mouse_step(Vector2(0, -12))
		await physics_frame
	check(level.eye.host == level.get_node("Terrain/RightWall"), "Independent mouse movement enters right wall through opened gate")
	check(level.eye.position.distance_to(level.bell.position) < 30.0, "Locator can reach bell in right wall")
	mouse_click()
	await frames(2)
	check(level.bell.activated and level.phase == level.Phase.BOARD, "Clicking near bell starts timed relay")
	for _i in range(10):
		mouse_step(Vector2(-12, 0))
		await physics_frame
	check(level.eye.host == level.ferry, "Locator can board horizontal platform before departure")
	await walk_to(400.0)
	check(level.plate_two.pressed, "Player can reach second pressure plate during relay")
	check(level._gate_one_open, "First connection remains latched after bell so player can leave plate one")
	var timeout := 1200
	while level.phase != level.Phase.CLIMB and timeout > 0 and level.active:
		await physics_frame
		timeout -= 1
	check(timeout > 0 and level.eye.host == level.ferry and level.ferry.position.x <= 576.01, "Horizontal platform carries locator to left handoff")
	check(level.upper.position.y >= 223.99, "Upper platform falls into alignment with relay")
	for _i in range(11):
		mouse_step(Vector2(0, -12))
		await physics_frame
	check(level.upper_entered and level.eye.host == level.upper, "Mouse can hurry upward into dropped platform")
	check(level._gate_two_open, "Holding second plate connects upper platform to exit passage")
	for _i in range(45):
		mouse_step(Vector2(-12, 0))
		await physics_frame
	check(level.phase == level.Phase.COMPLETE, "Entire L puzzle can be solved using real player and mouse controls")

	level.restart_run()
	await frames(4)
	check(not level._gate_one_open and not level._gate_two_open and not level.bell.activated, "Restart clears bell, connections, timers, and actor state")
	level.player.reset_to(Vector2(400, 490))
	level.upper.position.y = 224.0
	level.phase = level.Phase.CONNECT
	level.upper_entered = true
	await frames(10)
	level.eye.reset_to(Vector2(400, 256), level.gate_two)
	await frames(3)
	check(level._gate_two_open, "Second plate supports a locator inside the connecting bridge")
	await walk_to(500.0)
	check(level.phase == level.Phase.FAILED and not level._gate_two_open, "Leaving second plate interrupts occupied connecting bridge")

	level.restart_run()
	level.boarding_time = 0.02
	level.ferry_speed = 10000.0
	level.upper_drop_delay = 0.0
	level.upper_drop_speed = 10000.0
	level.climb_time = 0.05
	level._on_bell_rung()
	await frames(40)
	check(level.phase == level.Phase.FAILED, "Missing timed upward handoff fails with restart available")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("\nL puzzle checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
