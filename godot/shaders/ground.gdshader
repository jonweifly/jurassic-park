shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D detail_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D buildable_map : filter_nearest, repeat_disable;
uniform sampler2D usage_map : filter_linear, repeat_disable;
uniform sampler2D soil_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// 4m colour/height tiles, blended at two orientations to suppress repetition.
uniform sampler2D turf_surface : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_surface : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_surface : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_surface : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness = 0.0;
uniform bool build_preview = false;
uniform vec3 builder_position;
varying vec3 terrain_position;
varying vec3 terrain_normal;
float hash(vec2 p) { vec3 q=fract(vec3(p.x,p.y,p.x)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z); }
float noise(vec2 p) { vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void vertex() { terrain_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;terrain_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
vec4 surface_sample(sampler2D tex, vec2 uv, float patch) {
 vec4 a=texture(tex,uv);
 vec4 b=texture(tex,mat2(vec2(.8,.6),vec2(-.6,.8))*uv+vec2(.37,.71));
 // Narrow patch transitions retain individual blades/pebbles instead of
 // double-exposing two rotated textures across most of the clearing.
 return mix(a,b,smoothstep(.44,.56,patch));
}
void fragment() {
 vec3 original=COLOR.rgb;
 float saturation=max(original.r,max(original.g,original.b))-min(original.r,min(original.g,original.b));
 float grass=smoothstep(0.025,0.13,original.g-original.b);
 float snow=smoothstep(0.60,0.78,max(original.r,max(original.g,original.b)))*(1.0-smoothstep(0.08,0.20,saturation));
 float slope=1.0-clamp(terrain_normal.y,0.0,1.0);
 float rock=smoothstep(0.045,0.30,slope);
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
 vec3 usage=texture(usage_map,terrain_position.xz/256.0+vec2(.5)).rgb;
 float breakup=noise(terrain_position.xz*1.7);
 float camp=smoothstep(.12,.80,usage.r+(breakup-.5)*.20)*(1.0-snow);
 float floor_blend=smoothstep(.10,.82,usage.g)*(1.0-snow)*(1.0-rock);
 vec3 soil=texture(soil_map,terrain_position.xz*.31).rgb;
 vec3 forest=texture(forest_map,terrain_position.xz*.26).rgb;
 // Keep texture luminance in balance with the existing terrain palette.
 earth=mix(earth,forest*.90,floor_blend*.68);
 earth=mix(earth,soil*.82,camp*.78);
 earth*=.94+noise(terrain_position.xz*.075)*.12;
 // The open clearing receives a full grass-and-earth surface too, not just
 // tiny colour grain. Usage masks expose worn soil and fallen leaves naturally.
 vec2 surface_uv=terrain_position.xz*.25;
 float patch=noise(terrain_position.xz*.14);
 vec4 turf=surface_sample(turf_surface,surface_uv,patch);
 vec4 dirt=surface_sample(soil_surface,surface_uv,patch);
 vec4 leaves=surface_sample(litter_surface,surface_uv,patch);
 // Project along each axis so neither flat rocks nor steep cliffs smear.
 vec3 rock_weights=pow(abs(terrain_normal),vec3(4.0));
 rock_weights/=max(dot(rock_weights,vec3(1.0)),.001);
 vec4 stone=texture(rock_surface,terrain_position.zy*.25)*rock_weights.x
           +texture(rock_surface,terrain_position.xz*.25)*rock_weights.y
           +texture(rock_surface,terrain_position.xy*.25)*rock_weights.z;
 float grass_patches=smoothstep(.34,.65,noise(terrain_position.xz*.63)+noise(terrain_position.xz*1.8)*.16);
 float bare=clamp((1.0-grass)*.65+camp*.82+(1.0-grass_patches)*.42,0.0,1.0);
 vec4 surface=mix(turf,dirt,clamp(bare,0.0,1.0));
 surface=mix(surface,leaves,floor_blend*(1.0-camp)*.90);
 surface=mix(surface,stone,rock*.88);
 vec3 tint=mix(vec3(.95,1.02,.85),vec3(1.09,1.01,.88),broad);
 // Large readable colour masses retain the hill silhouette at an RTS camera
 // distance; the fine texture must not flatten every face into the same grain.
 earth=mix(earth,surface.rgb*tint*(.90+noise(terrain_position.xz*.055)*.20),(1.0-snow)*.84);
 float hollow=smoothstep(.54,.86,usage.b);
 float ridge=1.0-smoothstep(.20,.47,usage.b);
 vec3 face_tint=mix(vec3(.79,.83,.87),vec3(1.04,1.03,.94),smoothstep(.50,.98,terrain_normal.y));
 earth*=face_tint*(1.0-hollow*.18+ridge*.07);
 // Broad stone seams wrap over real banks instead of using a flat top-down decal.
 float strata=sin(terrain_position.y*5.4+noise(terrain_position.xz*.4)*1.7);
 earth*=1.0-rock*(1.0-snow)*smoothstep(.48,.91,strata)*.085;
 // Height-derived micro normal: low amplitude, mip-filtered; no distance shimmer.
 float relief_fade=1.0-smoothstep(.045,.20,length(fwidth(terrain_position.xz)));
 float h=(detail*.002+surface.a*.030*(1.0-snow))*relief_fade;
 vec3 q1=dFdx(VERTEX),q2=dFdy(VERTEX);
 vec3 n=normalize(NORMAL);
 vec3 r1=cross(q2,n),r2=cross(n,q1);
 float determinant=dot(q1,r1);
 vec3 gradient=sign(determinant)*(dFdx(h)*r1+dFdy(h)*r2);
 NORMAL=normalize(abs(determinant)*n-gradient);
 earth*=1.0-wetness*(1.0-snow)*0.16;
 ALBEDO=earth;
 AO=1.0-hollow*.25;
 float low_spots=1.0-smoothstep(.38,.65,surface.a);
 ROUGHNESS=mix(.94,.48,wetness*(.25+low_spots*.65)*(1.0-grass*.3));
 SPECULAR=0.18;
 if (build_preview && distance(terrain_position.xz,builder_position.xz)<12.0) {
  float allowed=texture(buildable_map,terrain_position.xz/256.0+vec2(0.5)).r;
  float stripe=step(0.78,fract((terrain_position.x+terrain_position.z)*2.0));
  ALBEDO=mix(ALBEDO,vec3(0.42,0.18,0.055),(1.0-allowed)*stripe*.42);
 }
}
