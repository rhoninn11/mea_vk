#!/bin/bash
PROJ_ROOT="$PWD"

zig build --watch -fincremental --prominent-compile-errors