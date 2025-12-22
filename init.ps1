$HERE=$PWD

$GLFW_REPO = "https://github.com/glfw/glfw.git"
$GLFW_VER = 3.4
$GLFW_DIR = "fs\_glfw"
$GLFW_INSTALL_DIR = "fs\glfw"


mkdir fs
git clone $GLFW_REPO -b $GLFW_VER $GLFW_DIR
mkdir $GLFW_DIR\build
cmake $GLFW_DIR -B $GLFW_DIR\build `
    -C zig.cmake -GNinja `
    -DBUILD_SHARED_LIBS=ON `
    -DGLFW_BUILD_EXAMPLES=OFF `
    -DGLFW_BUILD_TESTS=OFF `
    -DGLFW_BUILD_DOCS=OFF `
    "-DCMAKE_INSTALL_PREFIX=$GLFW_INSTALL_DIR"
cd $GLFW_DIR/build
ninja install
cd $HERE

# $VKZIG_REPO = "https://github.com/Snektron/vulkan-zig"
# $VKZIG_VER = "zig-0.15-compat"
# $VKZIG_DIR = "fs\vkzig"
# git clone $VKZIG_REPO -b $VKZIG_VER $VKZIG_DIR

$ZLS_REPO = "https://github.com/zigtools/zls"
$ZLS_VER = "0.15.1"
$ZLS_DIR = "fs\zls"

git clone $ZLS_REPO -b $ZLS_VER $ZLS_DIR