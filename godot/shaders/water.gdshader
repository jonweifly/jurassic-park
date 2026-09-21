shader_type spatial;
uniform vec4 deep_color : source_color = vec4(0.085,0.25,0.26,1.0);
uniform float weather_clock = 0.0;
uniform float wind_power = 0.16;
varying vec3 water_position;
void vertex() { water_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float a = water_position.x*1.8+water_position.z*0.7+weather_clock*(0.65+wind_power);
	float b = water_position.z*2.7-water_position.x*0.5-weather_clock*(0.45+wind_power);
	float ripple = sin(a)*cos(b);
	ALBEDO = deep_color.rgb + vec3(0.025,0.055,0.046)*ripple;
	NORMAL_MAP = normalize(vec3(cos(a)*0.11,sin(b)*0.11,1.0))*0.5+0.5;
	ROUGHNESS = 0.27;
	SPECULAR = 0.65;
}
