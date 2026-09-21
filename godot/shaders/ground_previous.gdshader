shader_type spatial;
render_mode diffuse_burley;
varying vec3 terrain_position;
float hash(vec2 p) {
	vec3 q = fract(vec3(p.x,p.y,p.x)*0.1031);
	q += dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { terrain_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float broad = noise(terrain_position.xz * 0.24);
	float grain = noise(terrain_position.xz * 7.0);
	float fine = mix(0.5, grain, 1.0-smoothstep(0.12,0.55,length(fwidth(terrain_position.xz))));
	vec3 original = COLOR.rgb;
	float saturation = max(original.r,max(original.g,original.b))-min(original.r,min(original.g,original.b));
	vec3 earth = mix(original, vec3(dot(original,vec3(0.3,0.5,0.2))),0.22);
	float grass = smoothstep(0.02,0.16,original.g-original.b) * smoothstep(0.01,0.08,saturation);
	earth = mix(earth, earth*vec3(0.80,0.94,0.92), grass);
	// Snow stays below clipping under daytime direct + ambient light.
	float snow = smoothstep(0.60,0.78,max(original.r,max(original.g,original.b))) * (1.0-smoothstep(0.08,0.20,saturation));
	earth = mix(earth,vec3(0.34,0.43,0.46),snow);
	ALBEDO = earth * (0.85 + broad*0.22 + fine*0.13);
	ROUGHNESS = 0.96;
}
