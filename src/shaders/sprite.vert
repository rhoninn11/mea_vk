#version 450

#define TAU 6.2831853071
#define PI 3.1415926538

// https://claude.ai/chat/59d09e00-0e18-4956-a051-34a4defa311a
layout(constant_id = 0) const int MAX_LIGHTS = 16;
layout(constant_id = 1) const float INTENSITY = 1.0;

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
layout(location = 1) flat out int v_tex_idx;


// group locked at the middle of the screan
// group gives info to precalculate surface
void main() {
    bool indepentednt = true;
    Instance m_inst = _storage.per_instance[gl_InstanceIndex];
    MatPack ems = _group.data.matrices;

    vec3 inst_pos = m_inst.offset_4d.xyz;

    vec3 base = a_pos;
    vec4 before_transform = vec4(base, 1.0);

    gl_Position = ems.proj * before_transform;
    
    v_uv = a_color.xy;

    int every = 32;
    if (indepentednt) {
        float time = _group.data.temporal.x*8;
        float times = int(time/every);
        int tex_idx = int(time - times*every);
        if (tex_idx >= every) {
            tex_idx = every-1;
        } 
        v_tex_idx = 32 + tex_idx;
    } else {
        float repurpused = round(m_inst.offset_2d.x);
        int inst_tex = int(repurpused);
        v_tex_idx = inst_tex;
    }
    
}
