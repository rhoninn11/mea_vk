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

layout(location = 0) out vec4 f_color;

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
}
