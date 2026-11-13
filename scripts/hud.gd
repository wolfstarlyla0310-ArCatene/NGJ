extends CanvasLayer

var status: Label
var statistics: Label
var margin_bar: ProgressBar
var overlay: PanelContainer
var overlay_title: Label
var overlay_text: Label
var chapter: Label
var metric_caption: Label
var controls_label: Label

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color(0.86, 0.86, 0.86))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)
	var top := MarginContainer.new()
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 36
	top.offset_right = -36
	top.offset_top = 26
	var header := HBoxContainer.new()
	top.add_child(header)
	var brand := VBoxContainer.new()
	header.add_child(brand)
	var name_label := _label("E C H O   /   同 行", 24)
	brand.add_child(name_label)
	chapter = _label("01   移动平台   ·   黑白白盒", 14)
	brand.add_child(chapter)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	statistics = _label("重生  00", 16)
	header.add_child(statistics)
	var footer_back := Panel.new()
	root.add_child(footer_back)
	footer_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer_back.offset_top = -128
	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = Color(0.025, 0.025, 0.025, 0.98)
	footer_style.border_color = Color(0.18, 0.18, 0.18)
	footer_style.border_width_top = 1
	footer_back.add_theme_stylebox_override("panel", footer_style)
	var bottom := MarginContainer.new()
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 36
	bottom.offset_right = -36
	bottom.offset_top = -105
	bottom.offset_bottom = -24
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	bottom.add_child(footer)
	status = _label("让身体与眼睛，一起抵达对岸。", 18)
	footer.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	footer.add_child(row)
	metric_caption = _label("感知点的视野余量", 13)
	row.add_child(metric_caption)
	margin_bar = ProgressBar.new()
	margin_bar.custom_minimum_size = Vector2(160, 6)
	margin_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin_bar.show_percentage = false
	margin_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.16, 0.16, 0.16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	margin_bar.add_theme_stylebox_override("background", back)
	margin_bar.add_theme_stylebox_override("fill", fill)
	row.add_child(margin_bar)
	controls_label = _label("A / D 或 ← / → 移动     空格跳跃     鼠标移动感知点     R 重来     Esc 暂停     F1 调试", 13)
	footer.add_child(controls_label)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = PanelContainer.new()
	overlay.custom_minimum_size = Vector2(590, 260)
	center.add_child(overlay)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.025, 0.025, 0.96)
	panel_style.border_color = Color(0.55, 0.55, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.content_margin_left = 36
	panel_style.content_margin_right = 36
	panel_style.content_margin_top = 28
	panel_style.content_margin_bottom = 28
	overlay.add_theme_stylebox_override("panel", panel_style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	overlay.add_child(content)
	overlay_title = _label("共用一双眼睛", 30)
	content.add_child(overlay_title)
	overlay_text = _label("", 17)
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_text.custom_minimum_size.x = 520
	content.add_child(overlay_text)
	_ignore_mouse(root)

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func show_message(title: String, text: String) -> void:
	overlay_title.text = title
	overlay_text.text = text
	overlay.show()

func update_state(deaths: int, eye_margin: float, finished: bool, debug: bool) -> void:
	statistics.text = "重生  %02d%s" % [deaths, "   /   调试视图" if debug else ""]
	margin_bar.value = clampf(eye_margin / 230.0, 0.0, 1.0) * 100.0
	if finished:
		status.text = "第一段已通过。可继续探索，或按 R 重新测试。"
	elif eye_margin < 50.0:
		status.text = "感知点快离开画面了——别把它落下。"
	else:
		status.text = "只见回声，不见本体。靠岸时，把感知点移入移动平台。"
