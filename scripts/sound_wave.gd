extends Node2D

var strength: float = 1.0
var age: float = 0.0
var lifetime: float = 2.4

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
	# The sonar renderer draws reflections; there is deliberately no expanding filled disc.
