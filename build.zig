const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // El renderer escribe cada pixel por software: en Debug va muy lento,
    // asi que por defecto compilamos en ReleaseFast.
    if (b.release_mode == .off) b.release_mode = .fast;
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "proyecto_03",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "raylib", .module = raylib }},
        }),
    });
    exe.root_module.linkLibrary(raylib_artifact);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Corre la simulacion del sistema solar");
    run_step.dependOn(&run_cmd.step);

    // Pruebas unitarias: solo usan tipos de raylib, no abren ventana.
    const test_step = b.step("test", "Corre las pruebas");
    const test_files = [_][]const u8{
        "src/mesh.zig",
        "src/raster.zig",
    };
    for (test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "raylib", .module = raylib }},
            }),
        });
        t.root_module.linkLibrary(raylib_artifact);
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
