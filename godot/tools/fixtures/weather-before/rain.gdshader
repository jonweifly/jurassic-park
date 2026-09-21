shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D ground_heights : filter_linear, repeat_disable;
uniform sampler2D roof_heights : filter_nearest, repeat_disable;
uniform float rain_gain = 0.0;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 uv = world_point.xz / 256.0 + vec2(0.5);
 float ground = texture(ground_heights,(uv*128.0+0.5)/129.0).r;
 float roof = texture(roof_heights,uv).r;
 if (world_point.y < max(ground+0.06,roof)) { discard; }
 ALBEDO = vec3(0.65,0.75,0.78);
 ALPHA = 0.20 * rain_gain;
}
