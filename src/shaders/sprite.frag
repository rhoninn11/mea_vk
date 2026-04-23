#version 450
#extension GL_EXT_nonuniform_qualifier : enable

#define TAU 6.2831853071


// whole data has is 16 x f32
layout(set = 0, binding = 0) uniform UniformData{
    vec2 offset_2d; 
    vec2 scale_2d;
    vec4 frag_data;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
} b_ubo;

layout(set = 2, binding = 0) uniform sampler2D tex_bindless[];

layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in int v_tex_idx;

layout(location = 0) out vec4 f_color;


void main() {
    vec4 tex_color = texture(tex_bindless[v_tex_idx], v_uv);
    f_color = tex_color;
}