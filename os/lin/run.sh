#!/bin/bash
PROJ_ROOT="$PWD"

# how to spawn on mint | ubuntu
    # wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | sudo apt-key add -
    # sudo wget -qO /etc/apt/sources.list.d/lunarg-vulkan-jammy.list https://packages.lunarg.com/vulkan/lunarg-vulkan-jammy.list
    # sudo apt update
    # sudo apt install libyaml-cpp-dev
    # sudo apt install vulkan-sdk
    # sudo apt install shaderc # for glslc

cd vkzig/examples
zig build main