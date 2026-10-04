shader_type spatial;
render_mode diffuse_burley, blend_mix, cull_disabled, depth_draw_never;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
	ROUGHNESS = 0.96;
	SPECULAR = 0.04;
}
