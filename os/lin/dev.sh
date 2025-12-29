#!/bin/bash
PROJ_ROOT="$PWD"

export PATH="$PATH:$PROJ_ROOT/os/lin/cmds"
export GLFW_LIB="$PROJ_ROOT/fs/glfw"

cd vkzig/examples
zig build main