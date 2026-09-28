shader_type spatial;
uniform float wetness=0.55;
varying vec3 local_p;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
void vertex(){ local_p=VERTEX; }
void fragment(){
    // Micro scales follow the authored UVs; silhouette comes from the mesh.
    vec2 p=UV*28.0;
    p.x += mod(floor(p.y),2.0)*.5;
    vec2 f=fract(p)-.5;
    float scale=1.0-smoothstep(.20,.49,length(f*vec2(1.0,1.12)));
    float mottle=sin(local_p.x*16.0+sin(local_p.z*9.0))*sin(local_p.y*19.0+local_p.z*3.0);
    float belly=1.0-smoothstep(1.52,2.1,local_p.y);
    vec3 color=mix(COLOR.rgb, COLOR.rgb*vec3(1.29,1.16,.97),belly*.38);
    float fade=1.0-smoothstep(.12,.5,length(fwidth(p)));
    ALBEDO=color*(.94+scale*.08*fade+mottle*.055);
    ROUGHNESS=mix(.78,.38,wetness)+(.5-scale)*.08*fade;
    SPECULAR=.4;
    NORMAL_MAP=normalize(vec3(f*.18*scale*fade,1.0))*.5+.5;
    NORMAL_MAP_DEPTH=.14;
}
