shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(0.28,0.40,0.22,1.0);
uniform bool vertex_color = false;
uniform bool leaf_detail = false;
#include "res://shaders/foliage_common.gdshaderinc"
varying float height_tint;
varying vec3 foliage_position;
varying flat float camera_pass;
varying float leaf_variation;
void vertex() {
	camera_pass = distance(INV_VIEW_MATRIX[3].xyz,camera_world_position) < 0.05 ? 1.0 : 0.0;
	VERTEX = wind_vertex(VERTEX,MODEL_MATRIX,TIME);
	foliage_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	height_tint = clamp(VERTEX.y*0.16+0.92,0.76,1.10);
	leaf_variation = sin(foliage_position.x*.73 + foliage_position.z*.41)*.045 + sin(foliage_position.z*1.7)*.025;
}
void fragment() {
	if (camera_pass > 0.5 && screen_pattern(FRAGCOORD.xy) > canopy_coverage(foliage_position)) { discard; }
	vec3 base = (vertex_color ? COLOR.rgb : tint.rgb)*height_tint;
	ALBEDO = base * vec3(.91+leaf_variation, .98+leaf_variation, .94+leaf_variation);
	if (leaf_detail) {
		vec2 leaf_uv = (fract(UV*4.0)-vec2(.06))/.88;
		float vein = 1.0-smoothstep(.015,.05,abs(leaf_uv.y-.5));
		float ribs = sin((leaf_uv.x-abs(leaf_uv.y-.5)*.55)*65.0);
		float fade = 1.0-smoothstep(.03,.16,length(fwidth(leaf_uv)));
		ALBEDO *= 1.0 + (vein*.10+ribs*.025)*fade;
	}
	ROUGHNESS = 0.92;
	SPECULAR = 0.0;
}
