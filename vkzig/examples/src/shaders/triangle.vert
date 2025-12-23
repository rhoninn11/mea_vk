#version 450

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec3 a_color;

// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform UniformData{
    vec2 offset_2d; 
    vec2 scale_2d;
    vec4 not_used_4d_0;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
} b_ubo;

struct PerInstanceData {
    vec2 offset_2d;
    vec2 scale_2d;
    vec4 not_used_4d_0;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
};

layout(set = 1, binding = 0) buffer InstanceData{
    PerInstanceData per_instance[];
} storage;

layout(location = 0) out vec3 v_color;

void main() {
    vec2 instance_offset = storage.per_instance[gl_InstanceIndex].offset_2d;
    vec2 prescaled_pos = a_pos * b_ubo.scale_2d;
    gl_Position = vec4(prescaled_pos + b_ubo.offset_2d + instance_offset, 0.0, 1.0);
    v_color = a_color;
}
