#version 450
#extension GL_EXT_nonuniform_qualifier : require

#define TAU 6.2831853071

struct PushData {
    mat4 model;
    uint inst_base;
    uint tex_base;
    uint mode;
    uint _not_used_1;
    uint _not_used_2;
    uint _not_used_3;
    uint _not_used_4;
    uint _not_used_5;
};
layout(push_constant) uniform PC { PushData data; } _pc;

// whole data has is 16 x f32

layout(set = 2, binding = 0) uniform sampler2D tex_bindless[];

layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in uint v_tex_idx;

layout(location = 0) out vec4 f_color;


void main() {
    if (_pc.data.mode == 1) {
        // f_color = vec4(1.0, 1.0, 1.0, 1.0);
        vec4 tex_color = texture(tex_bindless[nonuniformEXT(v_tex_idx)], v_uv);
        if (tex_color.a < 0.99) {
            discard;
        }
        f_color = tex_color;
    } else {
        vec4 tex_color = texture(tex_bindless[nonuniformEXT(v_tex_idx)], v_uv);
        if (tex_color.a < 0.99) {
            discard;
        }
        f_color = tex_color;
    }
}