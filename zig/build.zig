//! Note builder

const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "note",
        .root_source_file = b.path("./note.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const prod_release = b.option(bool, "prodRelease", "Use default values for the production release") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "prodRelease", prod_release);

    exe.root_module.addOptions("default_config", options);

    b.installArtifact(exe);
}
