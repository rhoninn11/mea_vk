#version 450

#define TAU 6.2831853071

layout(location = 0) in vec3 v_color;

// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform UniformData{
    vec2 offset_2d; 
    vec2 scale_2d;
    vec4 frag_data;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
} b_ubo;

struct PerInstanceData {
    vec2 offset_2d;
    float phase_offset;
    float spread_offset;
    vec2 wave_offset;
    vec4 not_used_4d_0;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
};

layout(set = 1, binding = 0) buffer InstanceData{
    PerInstanceData per_instance[];
} storage;

layout(location = 0) out vec4 f_color;

void main() {
    float progress = v_color.r;
    float spread = v_color.g;
    vec3 cos_in = vec3(progress-spread, progress, progress+spread) * TAU;
    vec3 emf_color_approx = (-cos(cos_in) + 1.0)*0.5-0.5; 
    f_color = vec4(emf_color_approx, 1.0);
}
