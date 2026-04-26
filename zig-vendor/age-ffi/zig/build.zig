const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the age module
    const age_module = b.addModule("age", .{
        .root_source_file = b.path("age.zig"),
    });

    // Build the example executable
    const example = b.addExecutable(.{
        .name = "age-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add the age module to the example
    example.root_module.addImport("age", age_module);

    // Link the Rust static library
    // Assumes the library has been built with: cargo build --release
    example.root_module.addLibraryPath(b.path("../target/release"));
    example.root_module.linkSystemLibrary("age_ffi", .{});

    // example.root_module.linkLibC();

    // Install the example
    b.installArtifact(example);

    // Create run step for the example
    const run_cmd = b.addRunArtifact(example);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    // Add a step to build the Rust library first
    const cargo_build = b.addSystemCommand(&[_][]const u8{
        "cargo",
        "build",
        "--release",
        "--manifest-path",
        "../Cargo.toml",
    });

    const cargo_step = b.step("cargo", "Build the Rust library");
    cargo_step.dependOn(&cargo_build.step);

    // Make the example depend on the cargo build
    example.step.dependOn(&cargo_build.step);

    // Add a clean step
    const cargo_clean = b.addSystemCommand(&[_][]const u8{
        "cargo",
        "clean",
        "--manifest-path",
        "../Cargo.toml",
    });

    const clean_step = b.step("clean", "Clean build artifacts");
    clean_step.dependOn(&cargo_clean.step);

    // Add test step
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    tests.root_module.addImport("age", age_module);
    tests.root_module.addLibraryPath(b.path("../target/release"));
    tests.root_module.linkSystemLibrary("age_ffi", .{});
    // tests.linkLibC();
    tests.step.dependOn(&cargo_build.step);

    const test_run = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_run.step);
}
