//! Tipo de textura (imagen en memoria) y como muestrearla sobre una esfera.
const std = @import("std");
const rl = @import("raylib");

const Vec3 = rl.Vector3;

/// Una textura por cada cuerpo celeste distinto.
pub const Kind = enum { sun, mercury, venus, earth, moon, mars, jupiter, neptune };
pub const KIND_COUNT = @typeInfo(Kind).@"enum".fields.len;

pub const Sample = struct {
    rgb: Vec3, // color 0..1
    mask: f32, // canal alpha de la textura: 0..1 (la Tierra lo usa para marcar tierra firme)
};

pub const Texture = struct {
    w: usize,
    h: usize,
    pixels: []rl.Color,

    pub fn deinit(self: *Texture, gpa: std.mem.Allocator) void {
        gpa.free(self.pixels);
    }

    fn at(self: *const Texture, x: usize, y: usize) rl.Color {
        return self.pixels[y * self.w + x];
    }

    /// Muestreo bilineal. u da la vuelta (longitud), v se limita (latitud).
    pub fn sample(self: *const Texture, u: f32, v: f32) Sample {
        const fw: f32 = @floatFromInt(self.w);
        const fh: f32 = @floatFromInt(self.h);
        const x = (u - @floor(u)) * fw - 0.5;
        const y = std.math.clamp(v, 0, 1) * (fh - 1);
        const x0f = @floor(x);
        const fx = x - x0f;
        const y0: usize = @intFromFloat(@floor(y));
        const fy = y - @floor(y);
        const y1 = @min(y0 + 1, self.h - 1);
        const xi: i64 = @intFromFloat(x0f);
        const w: i64 = @intCast(self.w);
        const xa: usize = @intCast(@mod(xi, w));
        const xb: usize = @intCast(@mod(xi + 1, w));

        const c00 = toSample(self.at(xa, y0));
        const c10 = toSample(self.at(xb, y0));
        const c01 = toSample(self.at(xa, y1));
        const c11 = toSample(self.at(xb, y1));
        const top = lerpSample(c00, c10, fx);
        const bot = lerpSample(c01, c11, fx);
        return lerpSample(top, bot, fy);
    }

    /// Muestrea con una direccion unitaria (punto de la esfera), proyeccion
    /// equirectangular: longitud -> u, latitud -> v.
    pub fn sampleDir(self: *const Texture, d: Vec3) Sample {
        const uv = dirToUv(d);
        return self.sample(uv[0], uv[1]);
    }
};

pub fn dirToUv(d: Vec3) [2]f32 {
    const lon = std.math.atan2(d.z, d.x);
    const lat = std.math.asin(std.math.clamp(d.y, -1, 1));
    return .{ lon / (2 * std.math.pi) + 0.5, 0.5 - lat / std.math.pi };
}

pub fn uvToDir(u: f32, v: f32) Vec3 {
    const lon = (u - 0.5) * 2 * std.math.pi;
    const lat = (0.5 - v) * std.math.pi;
    return Vec3.init(@cos(lat) * @cos(lon), @sin(lat), @cos(lat) * @sin(lon));
}

fn toSample(c: rl.Color) Sample {
    return .{
        .rgb = Vec3.init(@as(f32, @floatFromInt(c.r)) / 255, @as(f32, @floatFromInt(c.g)) / 255, @as(f32, @floatFromInt(c.b)) / 255),
        .mask = @as(f32, @floatFromInt(c.a)) / 255,
    };
}

fn lerpSample(a: Sample, b: Sample, t: f32) Sample {
    return .{ .rgb = a.rgb.lerp(b.rgb, t), .mask = a.mask + (b.mask - a.mask) * t };
}
