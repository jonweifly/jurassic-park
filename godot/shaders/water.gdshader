shader_type spatial;
// Depth-graded pond water. Water depth comes from the shared terrain
// height map the rain shader samples, so nothing here needs a depth prepass
// or screen copy: this project renders with gl_compatibility.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D ground_heights : filter_linear, repeat_disable;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.23,0.36,0.29,1.0);
uniform vec4 deep_color : source_color = vec4(0.050,0.155,0.185,1.0);
// Metres of water crossed before the bed stops tinting through.
uniform float depth_color_fade = 2.10;
// A short depth fade keeps ankle-deep crossings visible above their sandy bed.
uniform float shore_band = 0.28;
uniform float max_alpha = 0.90;
uniform float weather_clock = 0.0;
uniform float wind_power = 0.16;
uniform float ripple_normal_scale = 0.34;
uniform float water_roughness = 0.52;

varying vec3 water_position;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.x,p.y,p.x)*0.1031);
	q += dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

// Low-frequency, low-amplitude waves avoid specular aliasing while the camera moves.
float ripple_height(vec2 p, float t) {
	float h = noise(p*0.72 + vec2(0.86,0.51)*t*0.28)*0.62;
	h += noise(p*1.65 + vec2(-0.42,0.91)*t*0.42)*0.30;
	h += noise(p*3.10 + vec2(0.67,-0.74)*t*0.55)*0.08;
	return h;
}

void vertex() {
	water_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 grid = clamp(water_position.xz+vec2(128.0),vec2(0.0),vec2(255.999));
	ivec2 cell = ivec2(floor(grid));
	vec2 offset = fract(grid);
	float a = texelFetch(ground_heights,cell,0).r;
	float b = texelFetch(ground_heights,cell+ivec2(1,0),0).r;
	float c = texelFetch(ground_heights,cell+ivec2(0,1),0).r;
	float d = texelFetch(ground_heights,cell+ivec2(1,1),0).r;
	float bed = offset.x+offset.y <= 1.0
		? a+(b-a)*offset.x+(c-a)*offset.y
		: d+(c-d)*(1.0-offset.x)+(b-d)*(1.0-offset.y);
	float water_depth = max(water_position.y-bed,0.0);

	float gust = 0.55+0.45*clamp(wind_power,0.0,1.0);
	vec2 p = water_position.xz*0.48;
	float t = weather_clock;
	float e = 0.18;
	float h = ripple_height(p,t);
	vec2 slope = vec2(ripple_height(p+vec2(e,0.0),t)-h,ripple_height(p+vec2(0.0,e),t)-h)/e;
	float ripple_fade = 1.0-smoothstep(0.10,0.38,length(fwidth(water_position.xz)));
	slope *= gust*ripple_normal_scale*ripple_fade;

	// Warp only the inner fade band; the zero-depth edge remains transparent.
	float shore_warp = (noise(water_position.xz*0.11)-0.5)*0.045;
	float shore = smoothstep(0.0,shore_band,max(water_depth,0.0));
	shore *= smoothstep(0.0,shore_band*0.82,water_depth+shore_warp);
	shore *= smoothstep(0.0,0.75,COLOR.a);
	float depth_tint = smoothstep(0.0,depth_color_fade,water_depth);
	float bed_transmission = mix(0.38,1.0,smoothstep(0.18,0.85,water_depth));

	vec3 color = mix(shallow_color.rgb,deep_color.rgb,depth_tint);
	// Damp margin just inside the waterline: wet ground, not white foam.
	float rim = (1.0-smoothstep(0.0,shore_band*0.80,water_depth))*shore;
	color = mix(color,color*vec3(0.80,0.82,0.78),rim*0.50);
	// Broad slow patches keep large ponds from reading as one flat colour.
	color *= 0.97+0.06*noise(water_position.xz*0.09+vec2(weather_clock*0.012));

	float fresnel = pow(1.0-clamp(dot(normalize(NORMAL),normalize(-VERTEX)),0.0,1.0),3.2);

	float sight = mix(0.035,1.0,texture(visibility_map,water_position.xz/256.0+vec2(.5)).r);
	ALBEDO = color*sight;
	ALPHA = clamp(shore*max_alpha*bed_transmission+fresnel*0.10*shore,0.0,1.0);
	// Water meshes have no UV tangent frame. Supply a world-space wave normal
	// transformed to view space, stable under both camera rotation and panning.
	NORMAL = normalize((VIEW_MATRIX*vec4(-slope.x,1.0,-slope.y,0.0)).xyz);
	ROUGHNESS = clamp(water_roughness+(1.0-gust)*0.08+h*0.025,0.0,1.0);
	SPECULAR = 0.28*sight;
	METALLIC = 0.0;
}
