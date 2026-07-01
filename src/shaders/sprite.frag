#version 450
#extension GL_EXT_nonuniform_qualifier : require

#define TAU 6.2831853071

struct PushData {
    mat4 model;
    uint inst_base;
    uint tex_base;
    uint mode;
    uint _not_used_0;
    vec2 point2D;
    vec2 scale2D;
};

layout(push_constant) uniform PC { PushData data; } _pc;
// layout(set = 0, binding = 0) uniform UBO { UboData data; } _ubo;
// layout(set = 1, binding = 0) buffer readonly InstanceData{ Instance arr[]; } _storage;
layout(set = 2, binding = 0) uniform sampler2D tex_bindless[];

layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in uint v_tex_idx;
layout(location = 2) in float vv_limit;

layout(location = 0) out vec4 f_color; //out

vec4 sample_bindles(uint i, vec2 uv) {
    return texture(tex_bindless[nonuniformEXT(i)], uv);
}

void main() {
    vec4 tex_color = sample_bindles(v_tex_idx, v_uv);

    if (_pc.data.mode == 4) { // mono value tresholding
        float supse_to_use = vv_limit;
        if (tex_color.r < 0.6) {
            discard;
        }
        float base = (tex_color.r - 0.6) * 2.5;
        
        vec2 grad_uv = vec2(base, 0);
        vec4 grad_color = sample_bindles(32, grad_uv);
        f_color = vec4(grad_color.rgb, 1);
    }
    else { // crop ok space slices
        if (tex_color.a < 0.99) {
            discard;
        }
        f_color = tex_color;
    }
}