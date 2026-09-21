shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
uniform bool use_vertex_color = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform int source_cull_mode = 0;
uniform float normal_scale = 1.0;
uniform vec3 actor_focus;
uniform vec3 camera_axis;
uniform vec3 camera_world_position;
uniform float cutout_enabled = 0.0;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
varying vec3 world_position;
varying flat float camera_pass;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	camera_pass = distance(INV_VIEW_MATRIX[3].xyz, camera_world_position) < 0.05 ? 1.0 : 0.0;
}
void fragment() {
	if ((source_cull_mode == 0 && !FRONT_FACING) || (source_cull_mode == 1 && FRONT_FACING)) { discard; }
	vec3 offset = world_position - actor_focus;
	float along = dot(offset, camera_axis);
	float across = length(offset - camera_axis * along);
	float front = smoothstep(0.15, 0.6, along) * (1.0 - smoothstep(12.0, 17.0, along));
	float mask = (1.0 - smoothstep(0.45, 1.2, across)) * front * cutout_enabled;
	float pattern = fract(dot(floor(FRAGCOORD.xy), vec2(0.754877666, 0.56984029)));
	if (camera_pass > 0.5 && pattern > 1.0 - mask * 0.98) { discard; }
	vec3 color = tint.rgb;
	if (has_albedo) { color *= texture(albedo_tex, UV).rgb; }
	if (use_vertex_color) { color *= COLOR.rgb; }
	float sight = texture(visibility_map, world_position.xz / 256.0 + vec2(0.5)).r;
	ALBEDO = color * mix(0.035, 1.0, sight);
	ROUGHNESS = roughness * (has_roughness ? texture(roughness_tex, UV).r : 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; NORMAL_MAP_DEPTH = normal_scale; }
}
