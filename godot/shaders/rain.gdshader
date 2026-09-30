shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D ground_heights : filter_linear, repeat_disable;
uniform sampler2D roof_heights : filter_nearest, repeat_disable;
uniform float rain_gain = 0.0;
uniform vec2 rain_drift = vec2(0.0);
varying vec3 world_point;
varying flat float drop_seed;
varying vec2 drop_uv;
void vertex() {
 drop_seed = fract(sin(float(INSTANCE_ID)*127.1+17.0)*43758.5453);
 drop_uv = VERTEX.xy / vec2(0.018,0.24) + vec2(0.5);
 vec3 fall = normalize(vec3(-rain_drift.x,1.0,-rain_drift.y));
 vec3 right = normalize(cross(fall,INV_VIEW_MATRIX[2].xyz));
 float scale = length(MODEL_MATRIX[0].xyz);
 world_point = MODEL_MATRIX[3].xyz + (right*VERTEX.x+fall*VERTEX.y)*scale;
 VERTEX = (inverse(MODEL_MATRIX)*vec4(world_point,1.0)).xyz;
}
void fragment() {
 vec2 uv = world_point.xz / 256.0 + vec2(0.5);
 float ground = texture(ground_heights,(uv*256.0+0.5)/257.0).r;
 float roof = texture(roof_heights,uv).r;
 float floor_height = max(ground+0.06,roof);
 if (world_point.y < floor_height) { discard; }
 // Explicit mesh-space coordinates also work when particle UV animation is enabled.
 float edge = 1.0-smoothstep(0.30,0.50,abs(drop_uv.x-0.5));
 float core = 1.0-smoothstep(0.08,0.22,abs(drop_uv.x-0.5));
 float ends = smoothstep(0.0,0.10,drop_uv.y)*(1.0-smoothstep(0.78,1.0,drop_uv.y));
 // Bright wet-glass core over a softer falling streak; near-white highlight sells speed.
 ALBEDO = mix(vec3(0.56,0.68,0.74),vec3(0.86,0.93,0.97),core);
 float body = (0.42+drop_seed*0.16)*edge;
 float highlight = core*0.30*(0.6+0.4*drop_seed);
 ALPHA = clamp((body+highlight)*rain_gain*ends,0.0,1.0);
}
