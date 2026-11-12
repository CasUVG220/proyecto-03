//! Framebuffer en software: una imagen RGBA y un buffer de profundidad.
//! Es lo unico que "dibuja" el programa; raylib solo lo sube a la ventana.
const std = @import("std");
const rl = @import("raylib");

pub const Framebuffer = struct {
    width: i32,
    height: i32,
    pixels: []rl.Color, // se sube tal cual con updateTexture
    depth: []f32, // distancia en z de la camara; menor = mas cerca

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

    /// Limpia color y profundidad al inicio de cada cuadro.
    pub fn clear(self: *Framebuffer, color: rl.Color) void {
        @memset(self.pixels, color);
        @memset(self.depth, std.math.inf(f32));
    }

    /// Escribe un pixel sin mirar la profundidad (estrellas, efectos).
    pub fn put(self: *Framebuffer, x: i32, y: i32, c: rl.Color) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        self.pixels[@intCast(y * self.width + x)] = c;
    }
};
