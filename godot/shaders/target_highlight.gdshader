shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(0.65, 0.95, 0.75, 1.0);
void vertex() {
	VERTEX += NORMAL * 0.012;
}
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	ALBEDO = tint.rgb;
	ALPHA = 0.09 + rim * 0.45;
}
