extends SceneTree
## 验证同色重叠声场只保留并集外轮廓，异色重叠各自完整绘制。

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value:
		print("PASS  ", message)
	else:
		failures.append(message)
		push_error("FAIL  " + message)

func _container() -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	return node

func _make_field(container: Node2D, pos: Vector2, side: float, col: Color) -> SoundField:
	var field := SoundField.new()
	field.side_length = side
	field.lifetime = INF
	field.color = col
	container.add_child(field)
	field.global_position = pos
	field.current_side = side
	field.set_physics_process(false)
	return field

func _pieces_inside(field: SoundField, other: SoundField) -> int:
	var rect := other.drawn_world_rect()
	var count := 0
	for piece in field.visible_border_rects():
		if rect.has_point(piece.get_center()):
			count += 1
	return count

func _run() -> void:
	var white := Color.WHITE
	var blue := SoundField.color_for_level(1)

	# 1. 不重叠的同色场：各自保留 4 条边。
	var c1 := _container()
	var a1 := _make_field(c1, Vector2(0, 0), 64.0, white)
	var b1 := _make_field(c1, Vector2(200, 0), 64.0, white)
	check(a1.visible_border_rects().size() == 4, "Non-overlapping same-color field keeps four edges")
	check(b1.visible_border_rects().size() == 4, "Second non-overlapping field keeps four edges")

	# 2. 同色部分重叠：内部边段被去掉。
	var c2 := _container()
	var a2 := _make_field(c2, Vector2(0, 0), 64.0, white)
	var b2 := _make_field(c2, Vector2(24, 24), 64.0, white)
	check(_pieces_inside(a2, b2) == 0 and _pieces_inside(b2, a2) == 0,
		"Same-color overlap hides interior border segments")
	var right_shortened := false
	for piece in a2.visible_border_rects():
		if absf(piece.position.x - 31.0) < 2.0 and piece.size.y < 64.0:
			right_shortened = true
	check(right_shortened, "Overlapping edge is shortened instead of drawn through")
	check(a2.visible_border_rects().size() > 0 and b2.visible_border_rects().size() > 0,
		"Union outline still has visible border")

	# 3. 同色完全包含：内层不画边界，外层保留。
	var c3 := _container()
	var big := _make_field(c3, Vector2(0, 0), 128.0, white)
	var small := _make_field(c3, Vector2(0, 0), 32.0, white)
	check(small.visible_border_rects().is_empty(), "Contained same-color field has no visible border")
	check(big.visible_border_rects().size() == 4, "Outer same-color field keeps its border")

	# 4. 等级覆盖：黄 > 蓝 > 白；被覆盖场的重叠边消失，覆盖场保留。
	var c4 := _container()
	var yellow := SoundField.color_for_level(2)
	var white4 := _make_field(c4, Vector2(0, 0), 64.0, white)
	var blue4 := _make_field(c4, Vector2(24, 24), 64.0, blue)
	var yellow4 := _make_field(c4, Vector2(48, 48), 64.0, yellow)
	check(_pieces_inside(white4, blue4) == 0, "Blue covers the overlapped white border")
	check(_pieces_inside(blue4, yellow4) == 0, "Yellow covers the overlapped blue border")
	check(_pieces_inside(yellow4, blue4) > 0, "Yellow border is not covered by blue")
	check(white4.visible_border_rects().size() > 0 and blue4.visible_border_rects().size() > 0 \
		and yellow4.visible_border_rects().size() > 0,
		"Covering hierarchy keeps visible borders")
	check(white4.z_index < blue4.z_index and blue4.z_index < yellow4.z_index,
		"Field draw order is white < blue < yellow")

	# 4b. 红色等非标准色只与同色合并，不被标准色覆盖。
	var c4b := _container()
	var red := Color(1.0, 0.2, 0.2, 1.0)
	var red4 := _make_field(c4b, Vector2(0, 0), 64.0, red)
	var blue4b := _make_field(c4b, Vector2(24, 24), 64.0, blue)
	check(red4.visible_border_rects().size() == 4 and blue4b.visible_border_rects().size() == 4,
		"Red fields are not covered by standard colors")
	check(_pieces_inside(red4, blue4b) > 0, "Red border stays inside blue")

	# 5. 同色仅相接（共享一条边）：公共边保留，无缺口。
	var c5 := _container()
	var left5 := _make_field(c5, Vector2(0, 0), 64.0, white)
	var right5 := _make_field(c5, Vector2(64, 0), 64.0, white)
	check(left5.visible_border_rects().size() == 4 and right5.visible_border_rects().size() == 4,
		"Touching same-color fields keep the shared edge")

	# 6. 判定不变：get_rect / contains_point 仍用完整 side_length。
	var c6 := _container()
	var logic := _make_field(c6, Vector2(0, 0), 64.0, white)
	var logical_rect := logic.get_rect()
	check(absf(logical_rect.size.x - 64.0) < 0.01 and absf(logical_rect.size.y - 64.0) < 0.01,
		"Logical rect still uses the full side length")
	check(logic.contains_point(Vector2.ZERO) and not logic.contains_point(Vector2(100, 100)),
		"contains_point is unchanged")

	# 7. 不同父节点下的同色场互不遮挡（如收集品脉冲）。
	var c7a := _container()
	var c7b := _container()
	var solo_a := _make_field(c7a, Vector2(0, 0), 64.0, white)
	var solo_b := _make_field(c7b, Vector2(24, 24), 64.0, white)
	check(solo_a.visible_border_rects().size() == 4 and solo_b.visible_border_rects().size() == 4,
		"Same-color fields with different parents do not merge")

	# 8. 不可见的同类场不参与遮挡。
	var c8 := _container()
	var visible8 := _make_field(c8, Vector2(0, 0), 64.0, white)
	var hidden8 := _make_field(c8, Vector2(24, 24), 64.0, white)
	hidden8.visible = false
	check(visible8.visible_border_rects().size() == 4, "Hidden same-color field does not occlude")

	# 9. 零扩散声场（怪物外缘闪烁）第一帧就是满尺寸。
	var c9 := _container()
	var instant := SoundField.new()
	instant.side_length = 40.0
	instant.expand_duration = 0.0
	instant.lifetime = INF
	instant.color = Color(1.0, 0.2, 0.2, 1.0)
	c9.add_child(instant)
	instant.global_position = Vector2(0, 0)
	# physics_frame 在 _physics_process 之前触发，等两帧确保节点已处理。
	await physics_frame
	await physics_frame
	check(absf(instant.current_side - 40.0) < 0.01,
		"Zero-expand field is full size on the first physics frame")

	# 10. 完全分离的同色场互不遮挡（相交预筛路径）。
	var c10 := _container()
	var low10 := _make_field(c10, Vector2(0, 0), 64.0, white)
	var far10 := _make_field(c10, Vector2(0, 100), 64.0, white)
	check(low10.visible_border_rects().size() == 4 and far10.visible_border_rects().size() == 4,
		"Separated same-color fields keep all four edges")

	# 11. 标记 never_covered 的场（怪物外框）不被同色场覆盖，但仍会覆盖别人。
	var c11 := _container()
	var immune := _make_field(c11, Vector2(0, 0), 64.0, red)
	immune.never_covered = true
	var normal11 := _make_field(c11, Vector2(24, 24), 64.0, red)
	check(immune.visible_border_rects().size() == 4,
		"Never-covered field keeps all four edges despite same-color overlap")
	check(_pieces_inside(normal11, immune) == 0,
		"Normal same-color field is still covered by the never-covered field")

	for container in [c1, c2, c3, c4, c4b, c5, c6, c7a, c7b, c8, c9, c10, c11]:
		container.queue_free()
	await process_frame
	print("\nSound field border checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
