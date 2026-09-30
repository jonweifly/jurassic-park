shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

// Four open arcs and inward chevrons, using the HUD's muted antique gold.
// Driven by the click timer rather than TIME, so pause/repeated clicks are stable.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 marker_color : source_color = vec4(0.847059, 0.764706, 0.552941, 1.0);

float segment_distance(vec2 point, vec2 start, vec2 end) {
	vec2 line = end - start;
	float along = clamp(dot(point - start, line) / dot(line, line), 0.0, 1.0);
	return length(point - start - along * line);
}

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	float inward = 1.0 - pow(1.0 - clamp(progress / 0.8, 0.0, 1.0), 3.0);
	float rim_radius = mix(0.86, 0.72, inward);
	float aa = max(fwidth(radius), 0.012);
	float rim = 1.0 - smoothstep(0.023, 0.023 + aa, abs(radius - rim_radius));
	// Leave a small opening at each cardinal direction instead of a second ring.
	vec2 folded = abs(point);
	folded = vec2(max(folded.x, folded.y), min(folded.x, folded.y));
	float gap = smoothstep(radius * 0.179 - aa, radius * 0.179 + aa, folded.y);
	float tip = mix(0.49, 0.19, inward);
	float chevron_distance = segment_distance(folded, vec2(tip, 0.0), vec2(tip + 0.076, 0.076));
	float chevron = 1.0 - smoothstep(0.013, 0.013 + aa, chevron_distance);
	float fade = 1.0 - smoothstep(0.62, 1.0, progress);
	ALBEDO = marker_color.rgb;
	ALPHA = max(rim * gap, chevron * 0.75) * 0.90 * fade * marker_color.a;
}
