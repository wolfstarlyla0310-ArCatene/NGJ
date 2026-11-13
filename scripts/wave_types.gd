class_name WaveTypes
extends RefCounted

enum WaveType { WHITE, RED, BLUE }

static func color_for(type: WaveType) -> Color:
	match type:
		WaveType.RED: return Color(1.0, 0.15, 0.15)
		WaveType.BLUE: return Color(0.15, 0.4, 1.0)
	return Color.WHITE
