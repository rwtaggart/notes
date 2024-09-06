const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // const lib = b.addStaticLibrary(.{
    //     .name = "note",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);

    const sqlite3 = b.dependency("SQLite3", .{ .target = target, .optimize = optimize });
    const sqlite3_lib = b.addStaticLibrary(.{
        .name = "SQLite3",
        .target = target,
        .optimize = optimize,
    });

    sqlite3_lib.addCSourceFiles(.{
        .root = sqlite3.path(""),
        .files = &.{
            "sqlite3.c",
        },
        .flags = &.{
            "-Wall",
            "-Werror",
        },
    });
    // TODO: Are these required and what are they for?
    // sqlite3_lib.addIncludePath(sqlite3.path(""));
    // sqlite3_lib.installHeadersDirectory(sqlite3.path(""), "", .{ .include_extensions = &.{"h"} });
    b.installArtifact(sqlite3_lib);

    const exe = b.addExecutable(.{
        .name = "note",
        .root_source_file = b.path("src/note.zig"),
        .target = target,
        .optimize = optimize,
    });

    const use_home = b.option(bool, "useHome", "Use default values for the production release") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "USE_HOME", use_home);

    exe.root_module.addOptions("default_config", options);

    // Add SQLite3 library path
    // TODO: Incorporate the external dependency into the build process for cross-system support.
    // TODO: Figure out how this works:
    //       error: expected type 'Build.LazyPath', found '*const [16:0]u8'
    //       exe.addIncludePath("/path/to/include");
    //
    //       thread 2228929 panic: sub_path is expected to be relative to the build root, but was this absolute path:
    //       '/opt/homebrew/Cellar/sqlite/3.46.0/include'.
    //

    // TAKE OUT:
    // exe.addIncludePath(b.path("/opt/homebrew/Cellar/sqlite/3.46.0/include"));
    // exe.addLibraryPath(b.path("/opt/homebrew/Cellar/sqlite/3.46.0/lib"));
    // exe.linkSystemLibrary("sqlite3");

    // const sqlite3lib = b.addStaticLibrary(.{
    //     .name = "sqlite",
    // });

    // exe.linkLibC();
    exe.linkLibrary(sqlite3_lib);
    exe.addIncludePath(sqlite3_lib.getEmittedIncludeTree());

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    // FIXME: testing opts causes 'zig build test' to hang due to stderr / stdout messages.
    const opts_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/opts.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(opts_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/note.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
