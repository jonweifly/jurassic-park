shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform float rain_gain = 0.0;
uniform float weather_clock = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float radius = length(p) * 2.0;
	// Compatibility rendering does not expose INSTANCE_CUSTOM for this
	// lightweight splash pass. UV-driven phase keeps the ripple deterministic
	// while still allowing the weather clock to animate each quad.
	float phase = clamp(fract(weather_clock * 0.35 + UV.y), 0.0, 1.0);
	// The particle phase expands a thin ring and fades it before the next
	// sampled impact. A tiny clock shimmer keeps overlapping rings legible.
	float ring_radius = mix(0.08, 0.92, phase);
	float ring = 1.0 - smoothstep(0.02, 0.10, abs(radius-ring_radius));
	float inner = 1.0 - smoothstep(0.04, 0.34, radius);
	float edge = 1.0 - smoothstep(0.78, 1.0, radius);
	float fade = (1.0-phase) * (0.72+0.28*sin(weather_clock*2.4+phase*6.283));
	ALBEDO = vec3(0.56,0.77,0.84);
	ALPHA = clamp((ring*0.78+inner*0.10)*edge*fade*rain_gain,0.0,0.34);
}
