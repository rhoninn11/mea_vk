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
    vec4 new_usage; //  maybe just xy of front and up vec | to reconstruct from norm > nope
    //                  or if sign is hidden on higher 
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

float signDecoded(float val);
vec3 unzip(vec2 zipped);

// group locked at the middle of the screan
// group gives info to precalculate surface
void main() {
    bool indepentednt = false;
    Instance m_inst = _storage.per_instance[gl_InstanceIndex];
    MatPack ems = _group.data.matrices;
    
    // per instance transform matrix
    vec3 front = m_inst.new_usage.xyz;
    vec3 up = m_inst.depth_ctrl.xyz;
    vec3 right = cross(up, front);
    vec3 inst_pos = m_inst.offset_4d.xyz;

    mat4 per_inst_t = mat4(vec4(right, 0), vec4(up, 0), vec4(front, 0), vec4(inst_pos,1));
    vec4 before_ems = per_inst_t * vec4(a_pos, 1);

    gl_Position = ems.proj * ems.view * ems.model * before_ems;

    //to choose right slice per instance
    int slices_at = 32;
    float inst_tex_idx_f = m_inst.offset_4d.a;
    int inst_tex = int(inst_tex_idx_f);
    v_tex_idx = slices_at + inst_tex;
    
    v_uv = a_color.xy;
}
