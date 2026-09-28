shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength = 0.18;
uniform float wetness = 0.45;
uniform vec4 base_tint : source_color = vec4(1.0);
varying vec3 model_p;
void vertex() {
    model_p=VERTEX;
    vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    float sway=sin(TIME*.85+p.x*.21+p.z*.16)*.63+sin(TIME*1.7+p.z*.7)*.22;
    VERTEX.x += sway*wind_strength*clamp(VERTEX.y*.12,0.0,1.0);
    VERTEX.z += cos(TIME*.9+p.z*.18)*wind_strength*.32*clamp(VERTEX.y*.13,0.0,1.0);
}
void fragment() {
    float midrib=1.0-smoothstep(.008,.035,abs(UV.y-.5));
    float veins=sin((UV.x-abs(UV.y-.5)*.42)*100.0);
    ALBEDO=COLOR.rgb*base_tint.rgb*(.93+midrib*.13+veins*.035);
    ROUGHNESS=mix(.88,.54,wetness);
    SPECULAR=.30;
    BACKLIGHT=COLOR.rgb*base_tint.rgb*.12;
}
