#version 450
#extension GL_EXT_nonuniform_qualifier : enable

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
layout(set = 0, binding = 0) uniform UniformData{
    vec2 offset_2d; 
    vec2 scale_2d;
    vec4 frag_data;
    vec4 not_used_4d_1;
    vec4 not_used_4d_2;
} b_ubo;

layout(set = 2, binding = 0) uniform sampler2D tex_bindless[];

layout(location = 0) in vec2 v_uv;
layout(location = 1) in float v_progress;
layout(location = 2) in vec2 v_depth_shading;
layout(location = 4) in vec2 v_color_rest;

layout(location = 0) out vec4 f_color;

// TODO: use color texture loaded at tex_base;
// propably taylor series, but it is ai generated
vec3 inferno(float t) {
    const vec3 c0 = vec3(+0.0002, +0.0016, -0.0371);
    const vec3 c1 = vec3(+0.1059, +0.5664, +4.1179);
    const vec3 c2 = vec3(+11.6171, -3.9477, -16.2573);
    const vec3 c3 = vec3(-41.7093, +17.4577, +44.6451);
    const vec3 c4 = vec3(+77.1575, -33.4157, -82.2539);
    const vec3 c5 = vec3(-71.2877, +32.5539, +73.5881);
    const vec3 c6 = vec3(+25.0926, -12.2222, -23.1157);
    t = clamp(t, 0.0, 1.0);
    return clamp(c0+t*(c1+t*(c2+t*(c3+t*(c4+t*(c5+t*c6))))), 0.0, 1.0);
}


void main() {
    
    float progress = v_progress;
    vec2 uv = v_uv.rg;
    float spread = v_color_rest.r;
    float dim_lvl = v_color_rest.g;
    

    int v_tex_idx = 0;
    // in this case nonuniform is not specially needed i think
    vec4 tex_color = texture(tex_bindless[nonuniformEXT(v_tex_idx)], uv);

    // simple abberation impl
    vec3 cos_in = (vec3(progress) + vec3(-spread, 0, spread)) * TAU;
    vec3 emf_color_approx = (-cos(cos_in) + 1.0)*0.5-0.5; 
    
    f_color = vec4(dim_lvl*emf_color_approx, 1.0);
    f_color = f_color*tex_color;

    const float gate = v_depth_shading.x;
    const float h = v_depth_shading.y;
    vec3 level_color = f_color.xyz;

    if (gate > 0.5) {
        // vec4 inferno_alt = texture(tex_bindless[nonuniformEXT(3)], v_uv);
        level_color = inferno(h) * vec3(uv.x);
    }
    if (gate > 1.5) {
        level_color = vec3(1,0.9,0.7);
    }
    // if (gl_FrontFacing) {
        f_color = vec4(level_color, 1.0);
    
    if (_pc.data.mode == 1) {
        f_color = vec4(0.1, 0.3, 0.7, 1.0);
    } else if (_pc.data.mode == 2) {
        f_color = vec4(0.5, 0.1, 0.6, 1.0);
    }
    
    // } else {
    //     f_color = vec4(0, 1.0, 1.0, 1.0);
    // } 
}
