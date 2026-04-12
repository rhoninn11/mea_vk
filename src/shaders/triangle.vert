#version 450

#define TAU 6.2831853071
#define PI 3.1415926538

struct MatPack {
    mat4 model;
    mat4 view;
    mat4 proj;
};
struct GroupData{
    vec2 osc_scale; 
    vec2 scale;
    vec4 not_used_4d_0;
    vec4 temporal;
    vec4 not_used_4d_2;
    MatPack matrices;
};


// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform GroupDataUbo{
    GroupData data;
} _group;

struct Instance{
    vec2 offset_2d;
    vec2 other_offsets;
    vec4 new_usage;
    vec4 offset_4d;
    vec4 depth_ctrl;
    vec4 srgb;
};
layout(set = 1, binding = 0) buffer readonly InstanceData{
    Instance per_instance[];
} _storage;

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_color;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out float v_progress;
layout(location = 2) out vec2 v_depth_shading;
layout(location = 3) flat out int v_tex_idx;
layout(location = 4) out vec2 v_color_rest;


// group locked at the middle of the screan
// group gives info to precalculate surface
void main() {
    Instance m_inst = _storage.per_instance[gl_InstanceIndex];
    MatPack ems = _group.data.matrices;
    float gate = m_inst.depth_ctrl.x;
    float h = m_inst.depth_ctrl.y;

    vec3 pose_on_surface = m_inst.offset_4d.xyz;
    vec3 pos_scaled = a_pos * vec3(_group.data.scale.x);
    
    vec3 pos_im = pos_scaled;
    if (gate > 0.5) {
        pos_im = vec3(pos_scaled.x, pos_scaled.y*10*h, pos_scaled.z);
    }
    if (gate > 1.5) {
        pos_im = pos_scaled;
    }

    float phase_offset = m_inst.other_offsets.x;
    float spread_offset = m_inst.other_offsets.y;
    
    float phase = _group.data.temporal.x + phase_offset;

//  should be visible after depth testing
    float depth_osc = sin(_group.data.temporal.x + m_inst.new_usage.y)*0.49 + 0.5;
    float y_anim = depth_osc + gl_InstanceIndex*0.0001; // to combat depth flickering
    if (gate > 0.5) {
        y_anim = h*2;
    }
    if (gate > 1.5) {
        y_anim = h*2;
    }

    vec3 base = pos_im + pose_on_surface + vec3(0, y_anim, 0);

    vec4 before_transform = vec4(base, 1.0);
    gl_Position = ems.proj * ems.view * ems.model * before_transform;
    // gl_Position = before_transform; 
    v_uv.rg = a_color.rg;
    v_color_rest = vec2(spread_offset, y_anim);

    v_progress = a_color.r + m_inst.new_usage.x;

    v_depth_shading = m_inst.depth_ctrl.xy;
    v_tex_idx = 0;
}
