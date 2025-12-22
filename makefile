
run:
	command = zig build run -- -d ./fs
fetch_vkz:
	mkdir fs && cd fs && git clone https://github.com/Snektron/vulkan-zig --branch zig-0.15-compat

fetch_glfw:
	mkdir fs && cd fs && git clone https://github.com/glfw/glfw --branch 3.4
build_glfw:	
	mkdir fs/glfw/build && cd fs/glfw/build && cmake .. -GNinja -DGLFW_LIBRARY_TYPE=SHARED -DCMAKE_INSTALL_PREFIX="../../_glfw"
	mkdir fs/glfw/build && cd fs/glfw/build && cmake .. -GNinja -DCMAKE_INSTALL_PREFIX="../../_glfw"

fetch_glslc:
	mkdir fs && cd fs && git clone https://github.com/google/shaderc.git --branch v2025.2
build_glslc:
	mkdir -p fs/shaderc/build && pushd fs/shaderc && build && cmake .. -GNinja -DSHADERC_SKIP_TESTS=ON && popd

fill_path:
	$env:PATH += ";C:\Users\mwalesa\Desktop\dev\zig_oct\fs\shaderc\build\glslc"
	$env:PATH += ";C:\Users\mwalesa\Desktop\dev\zig_oct\zig_cmds"
	$env:PATH += ";C:\Users\mwalesa\Desktop\dev\zig_oct\fs\_glfw/bin"