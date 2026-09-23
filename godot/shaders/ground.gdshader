shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D detail_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D buildable_map : filter_nearest, repeat_disable;
uniform sampler2D usage_map : filter_linear, repeat_disable;
uniform sampler2D soil_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness = 0.0;
uniform bool build_preview = false;
uniform vec3 builder_position;
varying vec3 terrain_position;
varying vec3 terrain_normal;
float hash(vec2 p) { vec3 q=fract(vec3(p.x,p.y,p.x)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z); }
float noise(vec2 p) { vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void vertex() { terrain_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;terrain_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 vec3 original=COLOR.rgb;
 float saturation=max(original.r,max(original.g,original.b))-min(original.r,min(original.g,original.b));
 float grass=smoothstep(0.025,0.13,original.g-original.b);
 float snow=smoothstep(0.60,0.78,max(original.r,max(original.g,original.b)))*(1.0-smoothstep(0.08,0.20,saturation));
 float slope=1.0-clamp(terrain_normal.y,0.0,1.0);
 float rock=smoothstep(0.018,0.19,slope);
 vec4 fine=texture(detail_map,terrain_position.xz*0.36);
 vec4 mid=texture(detail_map,terrain_position.xz*0.105+vec2(0.32));
 float broad=noise(terrain_position.xz*0.22);
 vec3 earth=mix(original,vec3(dot(original,vec3(0.3,0.5,0.2))),0.12);
 earth=mix(earth,earth*vec3(0.71,0.86,0.70),grass);
 earth=mix(earth,vec3(0.27,0.29,0.245),rock*(1.0-snow)*0.68);
 earth=mix(earth,vec3(0.37,0.44,0.46),snow);
 float detail=mix(fine.r,fine.g,grass);
 detail=mix(detail,fine.b,rock);
 float litter=smoothstep(0.52,0.74,mid.a)*(1.0-rock)*(1.0-snow);
 earth=mix(earth,earth*vec3(0.83,0.76,0.65),litter*.34);
 earth*=0.88+broad*.12+(detail-.5)*.24+(mid.r-.5)*.16;
 // Camp soil and a leaf-covered forest floor give use and ecology a visible
 // footprint. The masks follow actual structures/trees, never alter navigation.
 vec2 usage=texture(usage_map,terrain_position.xz/256.0+vec2(.5)).rg;
 float breakup=noise(terrain_position.xz*1.7);
 float camp=smoothstep(.12,.80,usage.r+(breakup-.5)*.20)*(1.0-snow);
 float floor_blend=smoothstep(.10,.82,usage.g)*(1.0-snow)*(1.0-rock);
 vec3 soil=texture(soil_map,terrain_position.xz*.31).rgb;
 vec3 forest=texture(forest_map,terrain_position.xz*.26).rgb;
 // Keep texture luminance in balance with the existing terrain palette.
 earth=mix(earth,forest*.90,floor_blend*.68);
 earth=mix(earth,soil*.82,camp*.78);
 earth*=.94+noise(terrain_position.xz*.075)*.12;
 // Height-derived micro normal: low amplitude, mip-filtered; no distance shimmer.
 float h=detail*0.008;
 vec3 q1=dFdx(VERTEX),q2=dFdy(VERTEX);
 vec3 n=normalize(NORMAL);
 vec3 r1=cross(q2,n),r2=cross(n,q1);
 float determinant=dot(q1,r1);
 vec3 gradient=sign(determinant)*(dFdx(h)*r1+dFdy(h)*r2);
 NORMAL=normalize(abs(determinant)*n-gradient);
 earth*=1.0-wetness*(1.0-snow)*0.16;
 ALBEDO=earth;
 ROUGHNESS=mix(0.94,0.66,wetness*(1.0-grass*.5));
 SPECULAR=0.18;
 if (build_preview && distance(terrain_position.xz,builder_position.xz)<12.0) {
  float allowed=texture(buildable_map,terrain_position.xz/256.0+vec2(0.5)).r;
  float stripe=step(0.78,fract((terrain_position.x+terrain_position.z)*2.0));
  ALBEDO=mix(ALBEDO,vec3(0.42,0.18,0.055),(1.0-allowed)*stripe*.42);
 }
}
