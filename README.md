# mea_vk

next steps:
- test for problematic instance amount
- add 3d camera over data

learning vulkan in zig:
![screanshot](logo.png)

git diff --no-index a/ b/ > delta.patch
patch --verbose -p2 --directory=b < delta.patch

# linux devel: mint | ubuntu
    # wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | sudo apt-key add -
    # sudo wget -qO /etc/apt/sources.list.d/lunarg-vulkan-jammy.list https://packages.lunarg.com/vulkan/lunarg-vulkan-jammy.list
    # sudo apt update
    # sudo apt install libyaml-cpp-dev
    # sudo apt install vulkan-sdk # for validation layers
    # sudo apt install shaderc # for glslc