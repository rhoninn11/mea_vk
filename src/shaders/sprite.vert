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
struct PushData {
    mat4 model;
    uint inst_base;
    uint tex_base;
    uint mode;
    uint _not_used_0;
    vec2 point2D;
    vec2 scale2D;
};
struct UboData{
    vec2 osc_scale; 
    vec2 scale;
    vec4 not_used_4d_0;
    vec4 temporal;
    vec4 not_used_4d_2;
    MatPack matrices;
};

// 80B
struct Instance{
    vec2 offset_2d;
    vec2 other_offsets;
    vec4 new_usage; //  maybe just xy of front and up vec | to reconstruct from norm > nope
    //                  or if sign is hidden on higher 
    vec4 offset_4d;
    vec4 depth_ctrl;
    vec4 srgb;
};

// 16B
struct SmolInst{
    vec4 sizing;
};

layout(push_constant) uniform PC { PushData data; } _pc;
layout(set = 0, binding = 0) uniform UBO { UboData data; } _ubo;
layout(set = 1, binding = 0) buffer readonly InstanceData{ Instance arr[]; } _storage;
// layout(set = 2, binding = 0) uniform sampler2D tex_bindless[];

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_color;

layout(location = 0) out vec2 v_uv;
layout(location = 1) out uint v_tex_idx;

layout(location = 2) out float vv_limit;

float signDecoded(float val);
vec3 unzip(vec2 zipped);

// group locked at the middle of the screan
// group gives info to precalculate surface
void main() {
    uint inst_idx = _pc.data.inst_base + gl_InstanceIndex;
    MatPack mvp = _ubo.data.matrices;
    Instance m_inst = _storage.arr[inst_idx];

    if (_pc.data.mode == 1) { // what im dooing here?
        
        float scale = 48;
        vec3 char_scale = vec3(m_inst.offset_4d.xy, 1);
        vec3 char_offset = vec3(m_inst.offset_4d.zw, 0);
        // char_offset = vec3(0);
        vec4 delta = vec4(m_inst.offset_2d.x, m_inst.offset_2d.y, 0, 0);
        vec4 base = vec4((a_pos*char_scale + char_offset)*scale, 1);
        
        gl_Position = mvp.proj * mvp.view * _pc.data.model * (base + delta);
        // v_tex_idx = _pc.data.tex_base + floatBitsToUint(m_inst.other_offsets.x);
        v_uv = (a_color.xy*m_inst.new_usage.zw) + m_inst.new_usage.xy;
        v_tex_idx = _pc.data.tex_base;

    }else if (_pc.data.mode == 2 || _pc.data.mode == 4) {
        vec4 base = vec4(a_pos, 1);
        mat4 model = _pc.data.model;
        vv_limit = model[3][0];
        model[3][0] = 0;
        gl_Position = mvp.proj * mvp.view * _pc.data.model * base;
        v_tex_idx = _pc.data.tex_base;
        float s = _pc.data.scale2D.x;
        v_uv = a_color.xy * s + _pc.data.point2D;
    }else {
        // per instance transform matrix
        vec3 front = m_inst.new_usage.xyz;
        vec3 up = m_inst.depth_ctrl.xyz;
        vec3 right = cross(up, front);
        vec3 inst_pos = m_inst.offset_4d.xyz;

        mat4 per_inst_t = mat4(vec4(right, 0), vec4(up, 0), vec4(front, 0), vec4(inst_pos,1));
        vec4 before_ems = per_inst_t * vec4(a_pos, 1);

        gl_Position = mvp.proj * mvp.view * _pc.data.model * before_ems;
        v_tex_idx = _pc.data.tex_base + gl_InstanceIndex;
        v_uv = a_color.xy;
    }
}
