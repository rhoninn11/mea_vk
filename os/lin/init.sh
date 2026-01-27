HERE=$PWD

GLFW_REPO="https://github.com/glfw/glfw.git"
GLFW_VER=3.4
GLFW_DIR="fs/_glfw"
GLFW_INSTALL_DIR="fs/glfw"
CMAKE_ADDON="os/lin/zig.cmake"

# libx11-dev

mkdir fs
git clone ${GLFW_REPO} -b ${GLFW_VER} ${GLFW_DIR}
mkdir ${GLFW_DIR}/build
cmake ${GLFW_DIR} -B ${GLFW_DIR}/build \
    -C ${CMAKE_ADDON} -GNinja \
    -DBUILD_SHARED_LIBS=ON \
    -DGLFW_BUILD_EXAMPLES=OFF \
    -DGLFW_BUILD_TESTS=OFF \
    -DGLFW_BUILD_DOCS=OFF \
    -DGLFW_BUILD_X11=ON \
    -DGLFW_BUILD_WAYLAND=OFF \
    -DCMAKE_INSTALL_PREFIX=${GLFW_INSTALL_DIR} \
    -DX11_X11_LIB=/usr/lib/x86_64-linux-gnu/libX11.so # well... i have to work with broken version of cmake
cd ${GLFW_DIR}/build
ninja install
cd ${HERE}

# Will be needed:
# https://github.com/skvadrik/re2c/blob/master/BUILD.md

# ninja_repo="https://github.com/ninja-build/ninja.git"
# ninja_ver="v1.13.2"
# ninja_dir="fs/_ninja"
# ninja_install_dir="fs/ninja"

# git clone ${ninja_repo} -b ${ninja_ver} ${ninja_dir}

# $VKZIG_REPO = "https://github.com/Snektron/vulkan-zig"
# $VKZIG_VER = "zig-0.15-compat"https://github.com/Snektron/vulkan-zig
# $VKZIG_DIR = "fs\vkzig"
# git clone $VKZIG_REPO -b $VKZIG_VER $VKZIG_DIR

# $ZLS_REPO = "https://github.com/zigtools/zls"
# $ZLS_VER = "0.15.1"
# $ZLS_DIR = "fs\zls"

# git clone $ZLS_REPO -b $ZLS_VER $ZLS_DIR