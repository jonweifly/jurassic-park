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
	// Fixed frequencies: changing wind must not multiply elapsed time and jump phase.
	float phase = dot(model[3].xz,vec2(1.731,2.417));
	float gust = 0.52+0.24*sin(weather_clock*0.29+phase)+0.16*sin(weather_clock*0.13+phase*1.7);
	float tip = smoothstep(0.10,3.7,max(local.y,0.0));
	float breeze = sin(weather_clock*0.72+phase);
	float flutter = sin(weather_clock*2.1+p.x*5.3+p.z*4.7)*sin(weather_clock*1.37+p.y*7.1+phase);
	float response = 0.10+0.90*clamp(wind_power,0.0,1.0);
	// World-space movement has an explicit 3 cm bound even for tall/scaled trees.
	float sway = 0.024*tip*breeze*gust;
	float leaf = 0.006*smoothstep(0.03,0.6,max(local.y,0.0))*flutter;
	float displacement = (sway+leaf)*response*clamp(strength/0.055,0.0,1.0);
	vec3 offset = vec3(wind_direction.x,0.0,wind_direction.y)*displacement;
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
