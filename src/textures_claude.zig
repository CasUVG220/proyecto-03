//! ============================================================================
//!  TEXTURAS PROCEDURALES  -  CODIGO GENERADO POR CLAUDE (IA de Anthropic)
//! ============================================================================
//! Todo este archivo fue escrito por Claude. No hay imagenes en disco: cada
//! textura se calcula al arrancar a partir de ruido matematico.
//!
//! Idea general: para cada pixel (u, v) de la textura se calcula el punto 3D
//! equivalente sobre una esfera y se evalua ruido 3D en ese punto. Como el
//! ruido es 3D y no 2D, la textura no tiene costuras al darle la vuelta.
//!
//! Piezas:
//!   - hash3 / valueNoise / fbm : ruido suave en 3D (varias octavas = fbm)
//!   - worley                   : distancia al punto aleatorio mas cercano
//!                                (se usa para dibujar crateres)
//!   - una funcion por cuerpo   : decide el color de cada punto
const std = @import("std");
const rl = @import("raylib");

const texture = @import("texture.zig");
const Texture = texture.Texture;
const Kind = texture.Kind;
const Vec3 = rl.Vector3;

const TEX_W = 512;
const TEX_H = 256;

/// Genera todas las texturas, una por `texture.Kind`.
pub fn generateAll(gpa: std.mem.Allocator) ![texture.KIND_COUNT]Texture {
    var out: [texture.KIND_COUNT]Texture = undefined;
    var made: usize = 0;
    errdefer for (out[0..made]) |*t| t.deinit(gpa);
    inline for (0..texture.KIND_COUNT) |i| {
        out[i] = try generate(gpa, @enumFromInt(i));
        made += 1;
    }
    return out;
}

pub fn generate(gpa: std.mem.Allocator, kind: Kind) !Texture {
    const pixels = try gpa.alloc(rl.Color, TEX_W * TEX_H);
    for (0..TEX_H) |y| {
        const v = (@as(f32, @floatFromInt(y)) + 0.5) / TEX_H;
        for (0..TEX_W) |x| {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / TEX_W;
            const d = texture.uvToDir(u, v); // punto sobre la esfera unitaria
            pixels[y * TEX_W + x] = colorAt(kind, d);
        }
    }
    return .{ .w = TEX_W, .h = TEX_H, .pixels = pixels };
}

fn colorAt(kind: Kind, d: Vec3) rl.Color {
    return switch (kind) {
        .sun => sunColor(d),
        .mercury => craterColor(d, Vec3.init(0.55, 0.52, 0.48), Vec3.init(0.30, 0.28, 0.26), 4.0),
        .venus => venusColor(d),
        .earth => earthColor(d),
        .moon => craterColor(d, Vec3.init(0.72, 0.72, 0.70), Vec3.init(0.38, 0.38, 0.40), 3.0),
        .mars => marsColor(d),
        .jupiter => jupiterColor(d),
        .neptune => neptuneColor(d),
    };
}

// ------------------------------------------------------------------ ruido

fn hash3(ix: i32, iy: i32, iz: i32, seed: u32) f32 {
    var h: u32 = @as(u32, @bitCast(ix)) *% 374761393 +%
        @as(u32, @bitCast(iy)) *% 668265263 +%
        @as(u32, @bitCast(iz)) *% 2147483647 +% seed *% 2246822519;
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xFFFFFF)) / 16777215.0;
}

fn fade(t: f32) f32 {
    return t * t * (3 - 2 * t);
}

/// Ruido de valores 3D, devuelve 0..1.
fn valueNoise(p: Vec3, seed: u32) f32 {
    const fx = @floor(p.x);
    const fy = @floor(p.y);
    const fz = @floor(p.z);
    const ix: i32 = @intFromFloat(fx);
    const iy: i32 = @intFromFloat(fy);
    const iz: i32 = @intFromFloat(fz);
    const tx = fade(p.x - fx);
    const ty = fade(p.y - fy);
    const tz = fade(p.z - fz);

    var acc: f32 = 0;
    inline for (0..2) |dz| {
        inline for (0..2) |dy| {
            inline for (0..2) |dx| {
                const w = (if (dx == 0) 1 - tx else tx) * (if (dy == 0) 1 - ty else ty) * (if (dz == 0) 1 - tz else tz);
                acc += w * hash3(ix + @as(i32, dx), iy + @as(i32, dy), iz + @as(i32, dz), seed);
            }
        }
    }
    return acc;
}

/// Suma de octavas de ruido: detalle grande + detalle fino. Devuelve ~0..1.
fn fbm(p: Vec3, octaves: u32, seed: u32) f32 {
    var sum: f32 = 0;
    var amp: f32 = 0.5;
    var freq: f32 = 1;
    var norm: f32 = 0;
    for (0..octaves) |_| {
        sum += amp * valueNoise(p.scale(freq), seed);
        norm += amp;
        amp *= 0.5;
        freq *= 2;
    }
    return sum / norm;
}

/// Distancia (en celdas) al punto aleatorio mas cercano. Sirve para crateres.
fn worley(p: Vec3, seed: u32) f32 {
    const cx: i32 = @intFromFloat(@floor(p.x));
    const cy: i32 = @intFromFloat(@floor(p.y));
    const cz: i32 = @intFromFloat(@floor(p.z));
    var best: f32 = 10;
    var dz: i32 = -1;
    while (dz <= 1) : (dz += 1) {
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                const nx = cx + dx;
                const ny = cy + dy;
                const nz = cz + dz;
                const feature = Vec3.init(
                    @as(f32, @floatFromInt(nx)) + hash3(nx, ny, nz, seed),
                    @as(f32, @floatFromInt(ny)) + hash3(nx, ny, nz, seed + 1),
                    @as(f32, @floatFromInt(nz)) + hash3(nx, ny, nz, seed + 2),
                );
                best = @min(best, p.subtract(feature).length());
            }
        }
    }
    return best;
}

// ---------------------------------------------------------------- helpers

fn smooth(e0: f32, e1: f32, x: f32) f32 {
    const t = std.math.clamp((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
}

fn rgb(c: Vec3, mask: f32) rl.Color {
    return rl.Color.init(
        @intFromFloat(std.math.clamp(c.x, 0, 1) * 255),
        @intFromFloat(std.math.clamp(c.y, 0, 1) * 255),
        @intFromFloat(std.math.clamp(c.z, 0, 1) * 255),
        @intFromFloat(std.math.clamp(mask, 0, 1) * 255),
    );
}

fn mixc(a: Vec3, b: Vec3, t: f32) Vec3 {
    return a.lerp(b, std.math.clamp(t, 0, 1));
}

// ---------------------------------------------------------------- cuerpos

/// Sol: manchas de plasma naranja y amarilla (el shader las anima).
fn sunColor(d: Vec3) rl.Color {
    const n = fbm(d.scale(5), 5, 11);
    const cells = fbm(d.scale(14), 3, 12);
    const t = n * 0.7 + cells * 0.3;
    const dark = Vec3.init(0.85, 0.28, 0.02);
    const mid = Vec3.init(1.0, 0.62, 0.10);
    const hot = Vec3.init(1.0, 0.95, 0.55);
    const c = if (t < 0.5) mixc(dark, mid, t * 2) else mixc(mid, hot, (t - 0.5) * 2);
    return rgb(c, 1);
}

/// Mercurio y la Luna: gris con crateres (bordes claros, fondo oscuro).
fn craterColor(d: Vec3, light: Vec3, dark: Vec3, scale: f32) rl.Color {
    var c = mixc(dark, light, fbm(d.scale(6), 4, 21));
    var shade: f32 = 1;
    // Dos tamanos de crater.
    inline for (.{ .{ scale, 31 }, .{ scale * 2.7, 41 } }) |cfg| {
        const w = worley(d.scale(cfg[0]), cfg[1]);
        shade *= 1 - 0.38 * smooth(0.28, 0.05, w); // fondo oscuro
        const rim = @exp(-((w - 0.30) * (w - 0.30)) / 0.0016);
        shade += 0.22 * rim; // borde mas claro
    }
    c = c.scale(shade);
    return rgb(c, 1);
}

/// Venus: nubes amarillentas arremolinadas (con "domain warping").
fn venusColor(d: Vec3) rl.Color {
    const warp = Vec3.init(fbm(d.scale(3), 3, 51), fbm(d.scale(3), 3, 52), fbm(d.scale(3), 3, 53));
    const q = d.scale(3).add(warp.scale(1.8));
    const t = fbm(q, 5, 54);
    const a = Vec3.init(0.93, 0.80, 0.52);
    const b = Vec3.init(0.72, 0.50, 0.25);
    return rgb(mixc(b, a, t * 1.3 - 0.1), 1);
}

/// Tierra: oceanos, continentes, desiertos y casquetes polares.
/// El canal alpha marca tierra firme (255) u oceano (0) para el shader.
fn earthColor(d: Vec3) rl.Color {
    const h = fbm(d.scale(2.2), 6, 61);
    const sea_level: f32 = 0.50;
    const lat = @abs(d.y);

    if (h < sea_level) {
        const depth = smooth(sea_level, 0.25, h);
        const deep = Vec3.init(0.02, 0.07, 0.30);
        const shallow = Vec3.init(0.08, 0.35, 0.60);
        var c = mixc(shallow, deep, depth);
        // Hielo marino en los polos.
        c = mixc(c, Vec3.init(0.9, 0.95, 1.0), smooth(0.88, 0.95, lat));
        return rgb(c, 0);
    }
    const height = smooth(sea_level, 0.72, h);
    const dry = smooth(0.45, 0.62, fbm(d.scale(4), 4, 62)); // zonas secas
    const green = Vec3.init(0.13, 0.45, 0.14);
    const sand = Vec3.init(0.70, 0.60, 0.35);
    const rock = Vec3.init(0.42, 0.36, 0.30);
    var c = mixc(green, sand, dry * (1 - lat));
    c = mixc(c, rock, height * 0.8);
    c = mixc(c, Vec3.init(0.95, 0.97, 1.0), smooth(0.80, 0.90, lat + height * 0.1)); // nieve
    return rgb(c, 1);
}

/// Marte: oxido rojizo con manchas oscuras y casquetes pequenos.
fn marsColor(d: Vec3) rl.Color {
    const t = fbm(d.scale(3.5), 5, 71);
    const patches = smooth(0.45, 0.6, fbm(d.scale(7), 3, 72));
    var c = mixc(Vec3.init(0.78, 0.36, 0.17), Vec3.init(0.55, 0.22, 0.10), t);
    c = mixc(c, Vec3.init(0.30, 0.15, 0.10), patches * 0.5);
    const crater = worley(d.scale(6), 73);
    c = c.scale(1 - 0.25 * smooth(0.25, 0.05, crater));
    c = mixc(c, Vec3.init(0.95, 0.95, 0.97), smooth(0.90, 0.96, @abs(d.y)));
    return rgb(c, 1);
}

/// Jupiter: bandas horizontales turbulentas y la Gran Mancha Roja.
fn jupiterColor(d: Vec3) rl.Color {
    const lat = std.math.asin(std.math.clamp(d.y, -1, 1));
    const turb = fbm(Vec3.init(d.x * 6, d.y * 22, d.z * 6), 4, 81);
    const band = 0.5 + 0.5 * @sin(lat * 16 + turb * 3.5);
    const cream = Vec3.init(0.90, 0.82, 0.68);
    const orange = Vec3.init(0.78, 0.52, 0.30);
    const brown = Vec3.init(0.52, 0.32, 0.20);
    var c = if (band < 0.5) mixc(brown, orange, band * 2) else mixc(orange, cream, (band - 0.5) * 2);

    // Gran Mancha Roja: una elipse en el hemisferio sur.
    const lon = std.math.atan2(d.z, d.x);
    const dl = lon - 0.8;
    const dla = lat + 0.35;
    const e = (dl * dl) / 0.09 + (dla * dla) / 0.02;
    c = mixc(c, Vec3.init(0.72, 0.25, 0.15), smooth(1.0, 0.3, e));
    return rgb(c, 1);
}

/// Neptuno: azul profundo con vetas claras.
fn neptuneColor(d: Vec3) rl.Color {
    const bands = 0.5 + 0.5 * @sin(d.y * 9 + fbm(d.scale(3), 4, 91) * 4);
    const base = mixc(Vec3.init(0.08, 0.16, 0.55), Vec3.init(0.20, 0.38, 0.85), bands);
    const streak = smooth(0.62, 0.78, fbm(Vec3.init(d.x * 3, d.y * 9, d.z * 3), 4, 92));
    return rgb(mixc(base, Vec3.init(0.80, 0.90, 1.0), streak * 0.7), 1);
}

test "las texturas se generan y el oceano de la Tierra tiene alpha 0" {
    var t = try generate(std.testing.allocator, .earth);
    defer t.deinit(std.testing.allocator);
    var ocean: usize = 0;
    var land: usize = 0;
    for (t.pixels) |p| {
        if (p.a == 0) ocean += 1 else land += 1;
    }
    try std.testing.expect(ocean > 1000);
    try std.testing.expect(land > 1000);
}
