shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
#include "res://shaders/foliage_common.gdshaderinc"
varying vec2 sight_uv;
varying vec3 foliage_position;
varying flat float camera_pass;
void vertex() {
	camera_pass = distance(INV_VIEW_MATRIX[3].xyz,camera_world_position) < 0.05 ? 1.0 : 0.0;
	vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	sight_uv = p.xz / 256.0 + vec2(0.5);
	VERTEX = wind_vertex(VERTEX,MODEL_MATRIX,TIME);
	foliage_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	if (camera_pass > 0.5 && screen_pattern(FRAGCOORD.xy) > canopy_coverage(foliage_position)) { discard; }
	ALBEDO = vec3(mix(0.035,1.0,texture(visibility_map,sight_uv).r));
	ALPHA = 1.0;
}
