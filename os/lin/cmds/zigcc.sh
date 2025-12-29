#!/bin/bash
zig cc -target native-linux-gnu "$@"
# zig cc -target native-linux-musl "$@"