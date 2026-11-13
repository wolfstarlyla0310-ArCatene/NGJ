shader_type canvas_item;

uniform vec2 eye_position = vec2(160.0, 512.0);
uniform float sight_radius = 250.0;
uniform bool debug_visible = false;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	// Normal play is drawn by the sonar renderer: only reflected edges, no solid fill.
	COLOR = vec4(base.rgb, base.a * (debug_visible ? 1.0 : 0.0));
}
