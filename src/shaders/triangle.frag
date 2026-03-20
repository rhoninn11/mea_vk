#version 450

#define TAU 6.2831853071


// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform UniformData{
    vec2 offset_2d; 
    vec2 scale_2d;
    vec4 frag_data;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
} b_ubo;

layout(set = 2, binding = 0) uniform sampler2D texSampler;

layout(location = 0) in vec4 v_color;
layout(location = 1) in float v_progress;
layout(location = 2) in vec2 v_depth_shading;

layout(location = 0) out vec4 f_color;

vec3 inferno(float t) {
    const vec3 c0 = vec3(+0.0002, +0.0016, -0.0371);
    const vec3 c1 = vec3(+0.1059, +0.5664, +4.1179);
    const vec3 c2 = vec3(+11.6171, -3.9477, -16.2573);
    const vec3 c3 = vec3(-41.7093, +17.4577, +44.6451);
    const vec3 c4 = vec3(+77.1575, -33.4157, -82.2539);
    const vec3 c5 = vec3(-71.2877, +32.5539, +73.5881);
    const vec3 c6 = vec3(+25.0926, -12.2222, -23.1157);
    t = clamp(t, 0.0, 1.0);
    return clamp(c0+t*(c1+t*(c2+t*(c3+t*(c4+t*(c5+t*c6))))), 0.0, 1.0);
}

void main() {
    float progress = v_progress;
    vec2 uv = v_color.rg;
    float spread = v_color.b;
    vec4 tex_color = texture(texSampler, uv);
    vec3 cos_in = vec3(progress-spread, progress, progress+spread) * TAU;
    vec3 emf_color_approx = (-cos(cos_in) + 1.0)*0.5-0.5; 
    
    //vec3 mixed = emf_color_approx*tex_color.rgb;
    

    f_color = vec4(emf_color_approx*v_color.a, 1.0);
    f_color = f_color*tex_color;

    float trim_factor = 0.0;
    float shifted = ((v_depth_shading.y - trim_factor)/(1-trim_factor));
    vec3 level_color = v_depth_shading.x * inferno(shifted) + (1-v_depth_shading.x)*f_color.xyz;
    f_color = vec4(level_color, 1.0);
}
