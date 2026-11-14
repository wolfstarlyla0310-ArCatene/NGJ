@tool
extends EditorPlugin
## 房间编辑器：在大地图场景里添加房间框、拖拽矩形、校验地图配置。

const ROOMS_NAME := "Rooms"
const TERRAIN_NAME := "Terrain"
const PLAYER_NAME := "Player"
const OBJECTS_NAME := "Objects"
const CAMERA_NAME := "Camera"
const CAMERA_CONTROLLER_SCRIPT := "room_camera_controller.gd"
const MAP_SCRIPT := "world_map.gd"

const DEFAULT_ROOM_SIZE := Vector2(1152, 648)
const NEW_ROOM_GAP := 32.0
const SUGGESTED_MAX_WIDTH := 1152.0
const SUGGESTED_MAX_HEIGHT := 648.0

const LABEL_FONT_SIZE := 12
const LABEL_MARGIN := Vector2(4.0, 4.0)
const LABEL_COLOR := Color(0.78, 0.9, 1.0)
const LABEL_OUTLINE := Color(0.04, 0.08, 0.16, 0.9)
const LABEL_OUTLINE_SIZE := 4

var _btn_add_room: Button
var _btn_validate: Button
var _room_handles: RoomBoundsHandles = null
var _active_rooms: Array[Room] = []

func _enter_tree() -> void:
	_btn_add_room = _make_toolbar_button("添加房间", "在 Rooms 容器下新建一个房间框，摆在已有房间右侧", _on_add_room_pressed)
	_btn_validate = _make_toolbar_button("校验地图", "检查地形、玩家、相机、房间框与存档点配置", _on_validate_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, _btn_add_room)
	add_control_to_container(CONTAINER_TOOLBAR, _btn_validate)

	scene_changed.connect(_on_scene_changed)
	_on_scene_changed()

	_room_handles = RoomBoundsHandles.new()
	_room_handles.bounds_edited.connect(_on_bounds_edited)
	set_force_draw_over_forwarding_enabled()
	print("[房间编辑器] 插件已加载 —— 工具栏应出现「添加房间」「校验地图」")
	update_overlays()

func _exit_tree() -> void:
	for button in [_btn_add_room, _btn_validate]:
		if button != null:
			remove_control_from_container(CONTAINER_TOOLBAR, button)
			button.queue_free()
	_room_handles = null

func _handles(_object: Object) -> bool:
	_active_rooms = _selected_rooms()
	return not _active_rooms.is_empty()

func _selected_rooms() -> Array[Room]:
	var out: Array[Room] = []
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is Room:
			out.append(node)
		else:
			return []
	return out

func _edit(_object: Object) -> void:
	update_overlays()

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	if _room_handles != null:
		_room_handles.draw(viewport_control, _active_rooms)

func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if not _looks_like_map(root):
		return
	var rooms := _rooms_of(_find_node_by_name(root, ROOMS_NAME, "Node2D"))
	if rooms.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	if editor_viewport == null:
		return
	var view := editor_viewport.get_global_canvas_transform()
	for i in rooms.size():
		var text := _room_label(rooms[i], i + 1)
		if text.is_empty():
			continue
		var pos := view * rooms[i].get_rect().position + LABEL_MARGIN \
			+ Vector2(0.0, float(font.get_height(LABEL_FONT_SIZE)))
		viewport_control.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			LABEL_FONT_SIZE, LABEL_OUTLINE_SIZE, LABEL_OUTLINE)
		viewport_control.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			LABEL_FONT_SIZE, LABEL_COLOR)

func _room_label(room: Room, ordinal: int) -> String:
	var custom := room.room_name.strip_edges()
	return custom if not custom.is_empty() else str(ordinal)

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _room_handles == null:
		return false
	var consumed := _room_handles.gui_input(event, _active_rooms, get_undo_redo())
	if consumed:
		update_overlays()
	return consumed

func _on_bounds_edited() -> void:
	get_editor_interface().mark_scene_as_unsaved()

func _make_toolbar_button(text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.flat = true
	button.pressed.connect(callback)
	return button

func _on_scene_changed(_root: Node = null) -> void:
	var is_map := _looks_like_map(get_editor_interface().get_edited_scene_root())
	_btn_add_room.disabled = not is_map
	_btn_validate.disabled = not is_map

func _looks_like_map(root: Node) -> bool:
	if root == null:
		return false
	var script := root.get_script() as Script
	return script != null and script.resource_path.ends_with(MAP_SCRIPT)

# —— 添加房间 ——

func _on_add_room_pressed() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if not _looks_like_map(root):
		_warn("请先打开一个大地图场景（根节点需挂 world_map.gd）")
		return
	var rooms_root := root.get_node_or_null(ROOMS_NAME)
	if rooms_root == null:
		_warn("这个大地图场景里没有 %s 容器。\n请在根节点下新建一个 Node2D 并改名为 %s。"
			% [ROOMS_NAME, ROOMS_NAME])
		return
	var rect := _next_room_rect(rooms_root)
	var undo := get_undo_redo()
	undo.create_action("添加房间")
	undo.add_do_method(self, "_do_add_room", rooms_root, rect)
	undo.add_undo_method(self, "_undo_add_room", rooms_root)
	undo.commit_action()
	print("[房间编辑器] 已添加房间，矩形 ", rect)

func _do_add_room(rooms_root: Node, rect: Rect2) -> void:
	var room := Room.new()
	room.name = _unique_room_name(rooms_root)
	room.rect = rect
	rooms_root.add_child(room)
	room.owner = get_editor_interface().get_edited_scene_root()
	room.set_meta("_editor_added", true)

func _undo_add_room(rooms_root: Node) -> void:
	for i in range(rooms_root.get_child_count() - 1, -1, -1):
		var child := rooms_root.get_child(i)
		if child.has_meta("_editor_added"):
			child.remove_meta("_editor_added")
			rooms_root.remove_child(child)
			child.queue_free()
			return

func _next_room_rect(rooms_root: Node) -> Rect2:
	var rightmost := 0.0
	var has_room := false
	for child in rooms_root.get_children():
		var room := child as Room
		if room == null:
			continue
		has_room = true
		rightmost = maxf(rightmost, room.rect.end.x)
	var origin := Vector2(rightmost + NEW_ROOM_GAP, 0.0) if has_room else Vector2.ZERO
	return Rect2(origin, DEFAULT_ROOM_SIZE)

func _unique_room_name(rooms_root: Node) -> String:
	var index := rooms_root.get_child_count() + 1
	while rooms_root.has_node("Room%d" % index):
		index += 1
	return "Room%d" % index

# —— 校验地图 ——

func _on_validate_pressed() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if not _looks_like_map(root):
		_warn("请先打开一个大地图场景")
		return

	var problems: PackedStringArray = []
	var hints: PackedStringArray = []

	var terrain := _find_node_by_name(root, TERRAIN_NAME, "TileMapLayer") as TileMapLayer
	if terrain == null:
		problems.append("缺少 %s 节点（TileMapLayer）" % TERRAIN_NAME)
	else:
		if terrain.tile_set == null:
			problems.append("%s 没有设置 TileSet" % TERRAIN_NAME)
		elif terrain.get_used_cells().is_empty():
			problems.append("%s 上一个格子都没画" % TERRAIN_NAME)
		if not terrain.collision_enabled:
			problems.append("%s 的 collision_enabled 是 false —— 画出来的地形不会有碰撞" % TERRAIN_NAME)
		if terrain.tile_set != null and terrain.tile_set.get_physics_layers_count() == 0:
			problems.append("%s 的图集没有物理层 —— 请给图集加完整物理层" % TERRAIN_NAME)
		if not terrain.global_transform.is_equal_approx(Transform2D.IDENTITY):
			hints.append("%s 的全局变换不是单位变换；房间矩形是世界坐标，请保持地形在原点且无缩放。" % TERRAIN_NAME)
	if _count_node_by_name(root, TERRAIN_NAME, "TileMapLayer") > 1:
		hints.append("有多个节点叫 %s —— 运行时只认第一个，请只留一个。" % TERRAIN_NAME)

	var player := root.get_node_or_null(PLAYER_NAME)
	if player == null:
		problems.append("缺少 %s 节点（玩家）" % PLAYER_NAME)

	var camera := root.get_node_or_null(CAMERA_NAME)
	if camera == null or not (camera is Camera2D):
		problems.append("缺少 %s 节点（Camera2D）" % CAMERA_NAME)

	var controller := _find_camera_controller(root)
	if controller == null:
		problems.append("找不到房间相机控制器：请在根节点下新建一个 Node 并挂 room_camera_controller.gd。")
	else:
		if controller.get("camera") == null:
			problems.append("RoomCamera.camera 没有接线（请指向 %s）" % CAMERA_NAME)
		if controller.get("world") == null:
			problems.append("RoomCamera.world 没有接线（请指向根节点）")

	var rooms_root := _find_node_by_name(root, ROOMS_NAME, "Node2D")
	var rooms := _rooms_of(rooms_root)
	if rooms.is_empty():
		problems.append("一间房都没有：请在 %s 下新建 Node2D 并挂 room.gd" % ROOMS_NAME)
	else:
		_check_rooms(rooms, problems, hints)

	if terrain != null and not rooms.is_empty():
		var loose := 0
		for cell in terrain.get_used_cells():
			if RoomRegistry.room_of_cell(rooms, terrain, cell) == null:
				loose += 1
		if loose > 0:
			problems.append("有 %d 个地形格落在所有房间之外 —— 按 R 重置时它们不会还原。" % loose)
		_check_layer_cells(root, "Breakables/Lv1", rooms, hints)
		_check_layer_cells(root, "Breakables/Lv2", rooms, hints)
		_check_layer_cells(root, "Noise", rooms, hints)

	if player is Node2D and not rooms.is_empty():
		if RoomRegistry.room_at(rooms, (player as Node2D).global_position) == null:
			problems.append("玩家不在任何房间内 —— 开局相机找不到取景房间。")

	_check_checkpoints(root, rooms, problems, hints)

	if problems.is_empty() and hints.is_empty():
		print("[房间编辑器] 校验通过：", root.scene_file_path)
		_info("校验通过，没有发现问题")
		return
	for p in problems:
		printerr("[房间编辑器] 问题：", p)
	for h in hints:
		print("[房间编辑器] 提示：", h)
	if problems.is_empty():
		_info("没有发现错误，但有 %d 条提示：\n· " % hints.size() + "\n· ".join(hints))
	else:
		_warn("发现 %d 个问题、%d 条提示，详见「输出」面板\n· "
			% [problems.size(), hints.size()] + "\n· ".join(problems))

func _check_rooms(rooms: Array[Room], problems: PackedStringArray, hints: PackedStringArray) -> void:
	for i in rooms.size():
		var a := rooms[i]
		var ra := a.get_rect()
		if ra.size.x <= 0.0 or ra.size.y <= 0.0:
			problems.append("房间 %s 的矩形尺寸为零" % a.name)
			continue
		if ra.size.x > SUGGESTED_MAX_WIDTH or ra.size.y > SUGGESTED_MAX_HEIGHT:
			hints.append("房间 %s 比参考尺寸大（%.0f×%.0f，建议 ≤ %.0f×%.0f）—— 相机会自动缩放，但可能超出 min_zoom。"
				% [a.name, ra.size.x, ra.size.y, SUGGESTED_MAX_WIDTH, SUGGESTED_MAX_HEIGHT])
		if a.position.length() > 0.001:
			hints.append("房间 %s 的节点位置不是原点 —— rect 是局部坐标，建议保持原点、只改 rect。" % a.name)
		for j in range(i + 1, rooms.size()):
			if ra.intersects(rooms[j].get_rect(), false):
				hints.append("房间 %s 与 %s 的矩形有重叠 —— 归属由 %s 下的先后顺序决定。"
					% [a.name, rooms[j].name, ROOMS_NAME])

func _check_layer_cells(root: Node, path: String, rooms: Array[Room], hints: PackedStringArray) -> void:
	var layer := root.get_node_or_null(path) as TileMapLayer
	if layer == null:
		return
	var loose := 0
	for cell in layer.get_used_cells():
		if RoomRegistry.room_of_cell(rooms, layer, cell) == null:
			loose += 1
	if loose > 0:
		hints.append("%s 有 %d 格在房间外 —— R 重置不会还原它们。" % [path, loose])

func _check_checkpoints(root: Node, rooms: Array[Room], problems: PackedStringArray, hints: PackedStringArray) -> void:
	var checkpoints: Array[Node] = []
	_collect_checkpoints(root, checkpoints)
	var objects := _find_node_by_name(root, OBJECTS_NAME, "Node2D")
	for node in checkpoints:
		if objects == null or not objects.is_ancestor_of(node):
			problems.append("存档点 %s 不在 %s 容器下。" % [node.name, OBJECTS_NAME])
		if node is Node2D and not rooms.is_empty() \
				and RoomRegistry.room_at(rooms, (node as Node2D).global_position) == null:
			problems.append("存档点 %s 不在任何房间内。" % node.name)
	if rooms.is_empty():
		return
	for room in rooms:
		var found := false
		for node in checkpoints:
			if node is Node2D and room.contains_world_point((node as Node2D).global_position):
				found = true
				break
		if not found:
			hints.append("房间 %s 没有存档点 —— 进房时会记录玩家的进入位置作为存档点。" % room.name)

func _find_camera_controller(node: Node) -> Node:
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with(CAMERA_CONTROLLER_SCRIPT):
			return child
		var found := _find_camera_controller(child)
		if found != null:
			return found
	return null

func _find_node_by_name(root: Node, node_name: String, type_hint: String) -> Node:
	var direct := root.get_node_or_null(NodePath(node_name))
	if direct != null and direct.is_class(type_hint):
		return direct
	return _find_descendant(root, node_name, type_hint)

func _find_descendant(node: Node, node_name: String, type_hint: String) -> Node:
	for child in node.get_children():
		if child.name == node_name and child.is_class(type_hint):
			return child
		var found := _find_descendant(child, node_name, type_hint)
		if found != null:
			return found
	return null

func _count_node_by_name(node: Node, node_name: String, type_hint: String) -> int:
	var count := 0
	for child in node.get_children():
		if child.name == node_name and child.is_class(type_hint):
			count += 1
		count += _count_node_by_name(child, node_name, type_hint)
	return count

func _collect_checkpoints(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.has_signal(&"touched") and child.has_method(&"set_active"):
			out.append(child)
		_collect_checkpoints(child, out)

func _rooms_of(rooms_root: Node) -> Array[Room]:
	var result: Array[Room] = []
	if rooms_root == null:
		return result
	for child in rooms_root.get_children():
		var room := child as Room
		if room != null:
			result.append(room)
	return result

# —— 弹窗 ——

func _warn(message: String) -> void:
	_show_dialog("房间编辑器", message, true)

func _info(message: String) -> void:
	_show_dialog("房间编辑器", message, false)

func _show_dialog(title: String, message: String, is_warning: bool) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.ok_button_text = "知道了"
	if is_warning:
		dialog.dialog_close_on_escape = true
	var base := get_editor_interface().get_base_control()
	base.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
