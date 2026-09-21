shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(0.28,0.40,0.22,1.0);
uniform bool vertex_color = false;
#include "res://tools/fixtures/weather-before/foliage_common.gdshaderinc"
varying float height_tint;
varying vec3 foliage_position;
varying flat float camera_pass;
void vertex() {
	camera_pass = distance(INV_VIEW_MATRIX[3].xyz,camera_world_position) < 0.05 ? 1.0 : 0.0;
	VERTEX = wind_vertex(VERTEX,MODEL_MATRIX,TIME);
	foliage_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	height_tint = clamp(VERTEX.y*0.16+0.92,0.76,1.10);
}
void fragment() {
	if (camera_pass > 0.5 && screen_pattern(FRAGCOORD.xy) > canopy_coverage(foliage_position)) { discard; }
	ALBEDO = (vertex_color ? COLOR.rgb : tint.rgb)*height_tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.0;
}
