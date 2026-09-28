shader_type spatial;
uniform sampler2D soil_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D litter_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_map : source_color, filter_linear_mipmap, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 0.45;
varying vec3 world_p;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p = world_p.xz;
    float broad = noise(p*.20)*.65 + noise(p*.73)*.35;
    float path = 1.0-smoothstep(2.0,4.1,abs(p.x-sin(p.y*.12)*1.4)+broad*.65);
    vec3 forest = texture(litter_map,p*.38).rgb*vec3(.51,.58,.47);
    vec3 soil = texture(soil_map,p*.55).rgb*vec3(.59,.59,.54);
    vec3 gravel = texture(rock_map,p*1.2).rgb*.58;
    vec3 base = mix(forest,mix(soil,gravel,.32),path);
    float tire = (1.0-smoothstep(.16,.34,abs(abs(p.x-sin(p.y*.12)*1.4)-1.03)))*path;
    base *= 1.0-tire*.22;
    float water = smoothstep(.59,.73,noise(p*.46+4.0))*path*wetness;
    ALBEDO = base*(.83+broad*.30)*(1.0-wetness*.12);
    ALBEDO = mix(ALBEDO,vec3(.065,.095,.094),water*.64);
    ROUGHNESS = mix(.96,.14,water);
    SPECULAR = mix(.20,.65,water);
    METALLIC = water*.19;
    float grain = noise(p*42.0);
    NORMAL_MAP = normalize(vec3((grain-.5)*.13,(noise(p*38.0+71.0)-.5)*.13,1.0))*.5+.5;
    NORMAL_MAP_DEPTH = .42*(1.0-water);
}
