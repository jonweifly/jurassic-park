shader_type spatial;
render_mode unshaded, cull_disabled;
varying float height;
void vertex() {
 height = VERTEX.y;
 VERTEX.x += sin(TIME * 5.0 + VERTEX.y * 9.0) * 0.05 * VERTEX.y;
 VERTEX.z += cos(TIME * 4.3 + VERTEX.y * 7.0) * 0.04 * VERTEX.y;
}
void fragment() {
 ALBEDO = mix(vec3(1.0,0.72,0.16),vec3(0.85,0.14,0.015),smoothstep(0.25,0.9,height));
}
