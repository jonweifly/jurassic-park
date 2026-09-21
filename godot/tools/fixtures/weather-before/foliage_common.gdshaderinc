uniform float strength = 0.055;
uniform bool canopy_cutout = false;
uniform vec3 actor_focus = vec3(0.0);
uniform vec3 camera_axis = vec3(0.0,1.0,0.0);
uniform vec3 camera_world_position = vec3(0.0);
uniform float cutout_enabled = 0.0;
uniform float weather_clock = 0.0;
uniform float wind_power = 0.16;
uniform vec2 wind_direction = vec2(0.9,0.35);

vec3 wind_vertex(vec3 local, mat4 model, float clock) {
	vec3 p = (model * vec4(local,1.0)).xyz;
	float gust = 0.65+0.35*sin(weather_clock*0.37+p.x*0.08+p.z*0.05);
	float wave = sin(weather_clock*(0.85+wind_power)+p.x*0.41+p.z*0.32) + 0.25*sin(weather_clock*2.7+p.z*1.6);
	vec3 offset = vec3(wind_direction.x,0.0,wind_direction.y)*wave*strength*(0.25+wind_power*1.65)*gust*max(local.y+0.3,0.0);
	local += inverse(mat3(model))*offset;
	return local;
}

float canopy_coverage(vec3 p) {
	if (!canopy_cutout) { return 1.0; }
	vec3 offset = p-actor_focus;
	float along = dot(offset,camera_axis);
	float across = length(offset-camera_axis*along);
	float front = smoothstep(0.05,0.6,along)*(1.0-smoothstep(10.0,14.0,along));
	float mask = (1.0-smoothstep(0.65,1.45,across))*front*cutout_enabled;
	return 1.0-mask*0.98;
}

float screen_pattern(vec2 pixel) {
	// Stable screen-space stipple; no time noise or transparent sorting dependency.
	return fract(dot(floor(pixel),vec2(0.754877666,0.56984029)));
}
