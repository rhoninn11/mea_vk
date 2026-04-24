pub const DersMap = struct {
    files: []const []const u8,
    names: []const []const u8,
};

pub const ShdrUnit = struct {
    src: []const u8,
    unit: []const u8,
    unit_spv: []const u8,
};
