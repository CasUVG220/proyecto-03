const std = @import("std");
const rl = @import("raylib");

pub const Framebuffer = struct {
    width: i32,
    height: i32,
    pixels: []rl.Color,
    depth: []f32,

    pub fn init(gpa: std.mem.Allocator, width: i32, height: i32) !Framebuffer {
        const n: usize = @intCast(width * height);
        return .{
            .width = width,
            .height = height,
            .pixels = try gpa.alloc(rl.Color, n),
            .depth = try gpa.alloc(f32, n),
        };
    }

    pub fn deinit(self: *Framebuffer, gpa: std.mem.Allocator) void {
        gpa.free(self.pixels);
        gpa.free(self.depth);
    }

    pub fn clear(self: *Framebuffer, color: rl.Color) void {
        @memset(self.pixels, color);
        @memset(self.depth, std.math.inf(f32));
    }

    pub fn put(self: *Framebuffer, x: i32, y: i32, c: rl.Color) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        self.pixels[@intCast(y * self.width + x)] = c;
    }
};
