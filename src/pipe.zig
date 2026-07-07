const std = @import("std");
const gm = @import("graphics_context.zig");
const vk = @import("vulkan-zig");
const v = @import("vertex.zig");

const EmbedSpirv = [:0]align(4) const u8;

const vert_triangle align(@alignOf(u32)) = @embedFile("triangle_vert").*;
const frag_triangle align(@alignOf(u32)) = @embedFile("triangle_frag").*;

const vert_sprite align(@alignOf(u32)) = @embedFile("sprite_vert").*;
const frag_sprite align(@alignOf(u32)) = @embedFile("sprite_frag").*;

const vert_sdf align(@alignOf(u32)) = @embedFile("sdf_vert").*;
const frag_sdf align(@alignOf(u32)) = @embedFile("sdf_frag").*;
const Vertex = v.Vertex;

const slot_len: u8 = slots.len;
const slots: []const vk.ShaderStageFlags = &.{
    vk.ShaderStageFlags{ .vertex_bit = true },
    vk.ShaderStageFlags{ .fragment_bit = true },
};

const PSSCI = vk.PipelineShaderStageCreateInfo;
fn shaderStages(modules: [slot_len]vk.ShaderModule) [slot_len]PSSCI {
    var out: [slot_len]PSSCI = undefined;

    inline for (0..slot_len) |i| {
        out[i] = PSSCI{
            .stage = slots[i],
            .module = modules[i],
            .p_name = "main",
        };
    }
    return out;
}

// for selecting shaders?
pub const EBrush = enum(u8) {
    triangle,
    sprite,
    dsprite,
    fontsdf,
};

pub const Moduler = struct {
    gc: *const gm.GraphicsContext,
    layout: vk.PipelineLayout,
    pub fn initModuls(self: *const Moduler, lol: [slot_len]EmbedSpirv) ![slot_len]vk.ShaderModule {
        var out: [slot_len]vk.ShaderModule = undefined;

        inline for (0..slot_len) |i| {
            const mod = try self.gc.dev.createShaderModule(&.{
                .code_size = lol[i].len,
                .p_code = @ptrCast(lol[i].ptr),
            }, null);
            errdefer self.gc.dev.destroyShaderModule(mod, null);
            out[i] = mod;
        }
        return out;
    }

    pub fn destroyModules(self: *const Moduler, mods: [slot_len]vk.ShaderModule) void {
        for (mods[0..]) |mod|
            self.gc.dev.destroyShaderModule(mod, null);
    }

    pub fn createPipeline(
        self: *const Moduler,
        render_pass: vk.RenderPass,
        pt: EBrush,
    ) !vk.Pipeline {
        const src: [slot_len]EmbedSpirv = switch (pt) {
            .triangle => .{ vert_triangle[0..], frag_triangle[0..] },
            .sprite => .{ vert_sprite[0..], frag_sprite[0..] },
            .dsprite => .{ vert_sprite[0..], frag_sprite[0..] },
            .fontsdf => .{ vert_sdf[0..], frag_sdf[0..] },
        };
        const depth_test = switch (pt) {
            .triangle => true,
            .sprite => false,
            .dsprite => true,
            .fontsdf => false,
        };

        const mods = try self.initModuls(src);
        defer self.destroyModules(mods);

        const pssci = shaderStages(mods);
        return restOfPipeline(
            pssci[0..],
            self.gc,
            self.layout,
            render_pass,
            depth_test,
        );
    }

    pub fn destroyPipelin(self: *const Moduler, pipe: vk.Pipeline) void {
        self.gc.dev.destroyPipeline(pipe, null);
    }
};

fn restOfPipeline(
    pssci: []const vk.PipelineShaderStageCreateInfo,
    gc: *const gm.GraphicsContext,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    depth_test: bool,
) !vk.Pipeline {
    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = false },
        .front_face = .clockwise, // couse we assume Y axis flip
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const alt: vk.Bool32 = .false;
    const depth_stencil_state = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = if (depth_test) .true else alt,
        .depth_write_enable = if (depth_test) .true else alt,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = .false,

        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
        .stencil_test_enable = .false,
        .front = std.mem.zeroes(vk.StencilOpState),
        .back = std.mem.zeroes(vk.StencilOpState),
    };

    const gpci = &.{
        vk.GraphicsPipelineCreateInfo{
            .flags = .{},
            .stage_count = @intCast(pssci.len),
            .p_stages = pssci.ptr,
            .p_vertex_input_state = &pvisci,
            .p_input_assembly_state = &piasci,
            .p_tessellation_state = null,
            .p_viewport_state = &pvsci,
            .p_rasterization_state = &prsci,
            .p_multisample_state = &pmsci,
            .p_depth_stencil_state = &depth_stencil_state,
            .p_color_blend_state = &pcbsci,
            .p_dynamic_state = &pdsci,
            .layout = layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        },
    };

    var pipeline: vk.Pipeline = undefined;
    const result = try gc.dev.createGraphicsPipelines(
        .null_handle,
        gpci,
        null,
        @ptrCast(&pipeline),
    );
    _ = result;
    return pipeline;
}

pub fn createRenderPass(gc: *const gm.GraphicsContext, color_format: vk.Format, depth_format: vk.Format) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = color_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };
    // const depth_attachment = vk.AttachmentDescription{};
    const depth_attachment = vk.AttachmentDescription{
        .format = depth_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .depth_stencil_attachment_optimal,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };
    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
        .p_depth_stencil_attachment = &depth_attachment_ref,
    };

    const subpass_dependency = vk.SubpassDependency{
        .dst_subpass = 0,
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .src_stage_mask = .{
            .color_attachment_output_bit = true,
            .late_fragment_tests_bit = true,
        },
        .src_access_mask = .{
            .depth_stencil_attachment_write_bit = true,
        },
        .dst_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = true,
        },
        .dst_access_mask = .{
            .color_attachment_write_bit = true,
            .depth_stencil_attachment_write_bit = true,
        },
    };

    const att_arr: []const vk.AttachmentDescription = &.{ color_attachment, depth_attachment };

    const rpmvci: vk.RenderPassMultiviewCreateInfo = .{
        .subpass_count = 1,
    };
    _ = rpmvci;

    const render_pass_create_info: vk.RenderPassCreateInfo = .{
        .attachment_count = @intCast(att_arr.len),
        .p_attachments = att_arr.ptr,
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast(&subpass_dependency),
        // here we will pass multiview config
        .p_next = null,
    };

    return try gc.dev.createRenderPass(&render_pass_create_info, null);
}
