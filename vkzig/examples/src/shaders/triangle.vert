#version 450

struct PerInstanceData {
    vec2 offset_2d;
    vec2 other_offsets;
    vec4 new_usage;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
};

// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform UniformData{
    vec2 osc_scale; 
    vec2 scale_2d;
    vec4 not_used_4d_0;
    vec4 temporal;
    vec4 not_used_4d_2;
} b_ubo;
layout(set = 1, binding = 0) buffer readonly InstanceData{
    PerInstanceData per_instance[];
} storage;

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_color;

layout(location = 0) out vec3 v_color;
layout(location = 1) out float v_progress;

void main() {
    PerInstanceData per_inst = storage.per_instance[gl_InstanceIndex];

    vec2 instance_offset = per_inst.offset_2d;
    vec2 prescaled_pos = a_pos.xy * b_ubo.scale_2d;

    float phase_offset = per_inst.other_offsets.x;
    float spread_offset = per_inst.other_offsets.y;
    
    float phase = b_ubo.temporal.x + phase_offset;
    vec2 osc_offset = vec2(cos(phase), sin(phase)) * b_ubo.osc_scale;

    gl_Position = vec4(prescaled_pos + instance_offset + osc_offset, 0, 1.0);
    v_color.r = a_color.r;
    v_color.g = a_color.g;
    v_color.b = spread_offset;
    v_progress = a_color.r+per_inst.new_usage.x;
}
