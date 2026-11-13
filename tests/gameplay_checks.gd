extends SceneTree
## Integration checks against real Godot scenes and physics, without external test libraries.

var failures: Array[String] = []
var level: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		failures.append(description)
		push_error("FAIL  " + description)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _run() -> void:
	level = load("res://scenes/levels/first_crossing.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(3)
	var eye: WallEye = level.eye
	var player: EchoPlayer = level.player
	var ferry: WallPlatform = level.ferry
	check(not player.show_body_in_eye and not player.debug_visible, "Player body starts invisible")
	check(eye.can_occupy(eye.global_position), "Eye starts inside a valid wall")
	check(level.eye_is_visible(), "Spawn eye is inside the camera viewport")
	check(level._walls.size() == 3, "Level contains start, ferry, destination solids")

	eye.move_within_walls(Vector2(0, -1000))
	check(eye.global_position.y >= 460.0 - 0.01, "Eye cannot move out through a wall surface")
	eye.reset_to(Vector2(600, 512), level.start_wall)
	ferry.position.x = 900.0
	eye.move_within_walls(Vector2(1200, 0))
	check(eye.global_position.x <= 628.01, "Fast mouse motion cannot teleport over a gap")
	ferry.position.x = 641.0
	check(not eye.can_occupy(Vector2(640, 512)), "Even a one-pixel gap blocks an eye crossing")
	ferry.position.x = 640.0
	eye.reset_to(Vector2(610, 512), level.start_wall)
	eye.move_within_walls(Vector2(150, 0))
	check(eye.global_position.x > 700.0 and eye.host == ferry, "Eye can transfer into a docked moving platform")

	level.restart_run()
	player.reset_to(Vector2(768, 426))
	eye.reset_to(Vector2(768, 512), ferry)
	level._update_camera(0.0, true)
	await frames(8)
	check(player.is_on_floor(), "Player lands on moving platform surface")
	var player_before := player.global_position.x
	var eye_before := eye.global_position.x
	var ferry_before := ferry.global_position.x
	await frames(350)
	var ferry_travel := ferry.global_position.x - ferry_before
	check(ferry_travel > 70.0, "Ferry actually moves after its dock pause")
	check(absf((player.global_position.x - player_before) - ferry_travel) < 5.0, "Godot physics carries standing player with ferry")
	check(absf((eye.global_position.x - eye_before) - ferry_travel) < 1.0, "Eye is carried inside its moving host")
	check(eye.can_occupy(eye.global_position), "Carried eye remains fully inside its platform")
	# Play the entire crossing with real input and physics, without teleporting either actor.
	level.restart_run()
	ferry.paused = true
	Input.action_press("move_right")
	for _i in range(290):
		mouse_step(Vector2(2.0, 0))
		await physics_frame
	Input.action_release("move_right")
	await frames(20)
	if not (player.global_position.x > 700.0 and eye.host == ferry):
		print("Boarding diagnostic: player=", player.global_position, " eye=", eye.global_position, " host=", eye.host.name, " active=", level.active, " mouse=", Input.mouse_mode, " deaths=", level.deaths)
	check(player.is_on_floor() and player.global_position.x > 700.0 and eye.host == ferry, "Keyboard and mouse can board the same docked ferry")
	ferry.paused = false
	var dock_timeout := 1000
	while ferry.position.x < 1279.9 and dock_timeout > 0 and level.active:
		await physics_frame
		dock_timeout -= 1
	check(dock_timeout > 0 and level.active, "Both actors survive the ferry trip to the far dock")
	Input.action_press("move_right")
	for _i in range(330):
		mouse_step(Vector2(2.1, 0))
		await physics_frame
	Input.action_release("move_right")
	await frames(20)
	if not level.completed:
		print("Exit diagnostic: player=", player.global_position, " eye=", eye.global_position, " ferry=", ferry.position, " host=", eye.host.name, " active=", level.active, " reason=", level.last_death_reason)
	check(eye.host == level.get_node("Terrain/Destination") and eye.can_occupy(eye.global_position), "Mouse-controlled locator can leave ferry through far dock")
	check(level.completed and player.is_on_floor(), "Full first section is playable from spawn using independent controls")

	level._set_active(false)
	level._reset_world()
	var source := Vector2(300, 447)
	level._on_sound_emitted(source, 0.8)
	await process_frame
	check(level.waves.get_child_count() > 0, "Nearby invisible life generates visible sound wave effects")
	var wave_count: int = level.waves.get_child_count()
	level._on_sound_emitted(Vector2(5000, 447), 0.8)
	check(level.waves.get_child_count() == wave_count, "Sources outside hearing range produce no wave")
	for creature in level.creatures.get_children():
		check(not creature.debug_visible and creature.get_child_count() == 0, "Creature has no visible body in normal play")

	level.restart_run()
	player.reset_to(Vector2(2050, 426))
	eye.reset_to(Vector2(2000, 512), level.get_node("Terrain/Destination"))
	level._update_camera(0.0, true)
	await frames(12)
	if not level.completed:
		print("Destination diagnostic: player=", player.global_position, " eye=", eye.global_position, " floor=", player.is_on_floor(), " active=", level.active, " reason=", level.last_death_reason)
	check(level.completed, "Reaching the destination with both body and eye completes section")

	level.restart_run()
	var previous_deaths: int = level.deaths
	player.reset_to(Vector2(1400, 426))
	level._update_camera(0.0, true)
	await frames(2)
	check(level.deaths == previous_deaths + 1 and level.last_death_reason == "眼睛离开了视野", "Leaving eye outside the screen kills the player exactly once")
	await frames(110)
	check(level.active and player.global_position.distance_to(level.player_spawn) < 8.0, "Death automatically resets player, eye, and moving platform")
	check(eye.global_position.distance_to(level.eye_spawn) < 0.01 and level.eye_is_visible(), "Respawn restores a visible eye in its start wall")
	level.restart_run()
	await frames(8)
	Input.action_press("jump")
	await frames(10)
	Input.action_release("jump")
	check(player.global_position.y < level.player_spawn.y - 25.0 and not player.is_on_floor(), "Keyboard jump lifts the invisible body off the wall")

	level.restart_run()
	previous_deaths = level.deaths
	player.reset_to(Vector2(160, 1100))
	await frames(2)
	check(level.deaths == previous_deaths + 1 and level.last_death_reason == "身体坠入了深处", "Falling into void triggers death")
	level._set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("\nGameplay checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)

func mouse_step(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.window_id = root.get_window_id()
	motion.position = Vector2(640, 360)
	motion.relative = relative
	root.push_input(motion, true)
