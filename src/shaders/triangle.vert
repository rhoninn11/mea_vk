#version 450

#define TAU 6.2831853071
#define PI 3.1415926538

struct MatPack {
    mat4 model;
    mat4 view;
    mat4 proj;
};

// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform GroupData{
    vec2 osc_scale; 
    vec2 scale_2d;
    vec4 not_used_4d_0;
    vec4 temporal;
    vec4 not_used_4d_2;
    MatPack matrices;
} _group;

struct Instance{
    vec2 offset_2d;
    vec2 other_offsets;
    vec4 new_usage;
    vec4 offset_4d;
    vec4 depth_control;
};
layout(set = 1, binding = 0) buffer readonly InstanceData{
    Instance per_instance[];
} _storage;

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_color;

layout(location = 0) out vec4 v_color;
layout(location = 1) out float v_progress;

// group locked at the middle of the screan
// group gives info to precalculate surface
void main() {
    Instance m_inst = _storage.per_instance[gl_InstanceIndex];
    MatPack ems = _group.matrices;

    vec3 pose_on_surface = m_inst.offset_4d.xyz;
    vec3 prescaled_pos = a_pos * vec3(_group.scale_2d.x);

    float phase_offset = m_inst.other_offsets.x;
    float spread_offset = m_inst.other_offsets.y;
    
    float phase = _group.temporal.x + phase_offset;

//  should be visible after depth testing
    float depth_osc = sin(_group.temporal.x + m_inst.new_usage.y)*0.49 + 0.5;
    float float_anim = depth_osc + gl_InstanceIndex*0.0001; // to combat depth flickering

    float gate = m_inst.depth_control.x;
    float h = m_inst.depth_control.y;
    float_anim = gate*h + (1-gate)*float_anim;

    vec3 base = prescaled_pos + pose_on_surface + vec3(0, float_anim, 0);

    vec4 before_transform = vec4(base, 1.0);
    gl_Position = ems.proj * ems.view * ems.model * before_transform;
    // gl_Position = before_transform; 
    v_color.rg = a_color.rg;
    v_color.b = spread_offset;
    v_color.a = float_anim;

    v_progress = a_color.r + m_inst.new_usage.x;
}
