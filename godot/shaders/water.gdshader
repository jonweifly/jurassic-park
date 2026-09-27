shader_type spatial;
// Depth-graded pond water. Water depth comes from the same 129x129 terrain
// height map the rain shader samples, so nothing here needs a depth prepass
// or screen copy: this project renders with gl_compatibility.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D ground_heights : filter_linear, repeat_disable;
uniform sampler2D water_coverage : filter_linear, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.32,0.47,0.41,1.0);
uniform vec4 deep_color : source_color = vec4(0.050,0.155,0.185,1.0);
// Metres of water crossed before the bed stops tinting through.
uniform float depth_color_fade = 2.10;
// Waterline feather: the mesh edge dissolves across this many metres of depth.
uniform float shore_band = 0.55;
uniform float max_alpha = 0.90;
uniform float weather_clock = 0.0;
uniform float wind_power = 0.16;

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

// Three octaves drifting on separate headings; a sine lattice reads as a grid.
float ripple_height(vec2 p, float t) {
	float h = noise(p*1.35 + vec2(0.86,0.51)*t*0.60)*0.52;
	h += noise(p*3.10 + vec2(-0.42,0.91)*t*0.95)*0.31;
	h += noise(p*7.40 + vec2(0.67,-0.74)*t*1.55)*0.17;
	return h;
}

void vertex() {
	water_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 grid = clamp((water_position.xz+vec2(128.0))*0.5,vec2(0.0),vec2(127.999));
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
	vec2 p = water_position.xz*0.85;
	float t = weather_clock;
	float e = 0.11;
	float h = ripple_height(p,t);
	vec2 slope = vec2(ripple_height(p+vec2(e,0.0),t)-h,ripple_height(p+vec2(0.0,e),t)-h)/e;
	slope *= gust;

	// Shore feather. The boundary follows real depth, not the cell grid, so a
	// square mesh edge no longer ends on a hard line.
	float shore = smoothstep(0.0,shore_band,water_depth);
	float coverage = texture(water_coverage,water_position.xz/256.0+vec2(0.5)).r;
	shore *= smoothstep(0.5,0.9,coverage);
	float depth_tint = smoothstep(0.0,depth_color_fade,water_depth);

	vec3 color = mix(shallow_color.rgb,deep_color.rgb,depth_tint);
	// Damp margin just inside the waterline: wet ground, not white foam.
	float rim = (1.0-smoothstep(0.0,shore_band*0.80,water_depth))*shore;
	color = mix(color,color*vec3(0.80,0.82,0.78),rim*0.50);
	// Broad slow patches keep large ponds from reading as one flat colour.
	color *= 0.95+0.10*noise(water_position.xz*0.09+vec2(weather_clock*0.02));

	float fresnel = pow(1.0-clamp(dot(normalize(NORMAL),normalize(-VERTEX)),0.0,1.0),3.2);

	ALBEDO = color;
	ALPHA = clamp(shore*max_alpha+fresnel*0.10*shore,0.0,1.0);
	NORMAL_MAP = normalize(vec3(-slope.x*0.55,-slope.y*0.55,1.0))*0.5+0.5;
	NORMAL_MAP_DEPTH = 0.85*gust;
	ROUGHNESS = clamp(mix(0.14,0.32,1.0-gust)+h*0.06,0.0,1.0);
	SPECULAR = 0.62;
	METALLIC = 0.0;
}
