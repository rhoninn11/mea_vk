const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});

const vk = @import("third_party/vk.zig");

pub const glfwGetRequiredInstanceExtensions = c.glfwGetRequiredInstanceExtensions;
// usually the GLFW vulkan functions are exported if Vulkan is included,
// but since thats not the case here, they are manually imported.

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
