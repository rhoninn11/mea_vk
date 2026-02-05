#version 450


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
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
};
layout(set = 1, binding = 0) buffer readonly InstanceData{
    Instance per_instance[];
} _storage;

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_color;

layout(location = 0) out vec3 v_color;
layout(location = 1) out float v_progress;

// group locked at the middle of the screan
void main() {
    Instance m_inst = _storage.per_instance[gl_InstanceIndex];
    MatPack ems = _group.matrices;

    vec2 instance_offset = m_inst.offset_2d;
    vec2 prescaled_pos = a_pos.xy * _group.scale_2d;

    float phase_offset = m_inst.other_offsets.x;
    float spread_offset = m_inst.other_offsets.y;
    
    float phase = _group.temporal.x + phase_offset;
    vec2 osc_offset = vec2(cos(phase), sin(phase)) * _group.osc_scale;
    osc_offset = vec2(0,0);

//  should be visible after depth testing
    float depth_osc = sin(_group.temporal.x + m_inst.new_usage.y)*0.49 + 0.5;
    depth_osc += gl_InstanceIndex*0.001;
    vec4 before_transform = vec4(prescaled_pos + instance_offset + osc_offset, depth_osc, 1.0);
    gl_Position = ems.proj * ems.view * before_transform; 
    // gl_Position = before_transform; 
    v_color.rg = a_color.rg;
    v_color.b = spread_offset;
    v_progress = a_color.r + m_inst.new_usage.x;
}
