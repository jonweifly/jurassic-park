shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(.10,.16,.16,1.0);
uniform float wetness = 0.55;
void fragment() {
    float ripple=sin(UV.x*92.0+TIME*.9)*cos(UV.y*83.0-TIME*.5);
    NORMAL_MAP=normalize(vec3(ripple*.075,cos(UV.x*70.0+UV.y*96.0+TIME)*.06,1.0))*.5+.5;
    ALBEDO=tint.rgb;
    ROUGHNESS=.14;
    METALLIC=.50;
    SPECULAR=.75;
}
