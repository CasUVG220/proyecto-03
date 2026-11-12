//! Skybox: un cielo de estrellas lejanas. Cada estrella es solo una direccion;
//! como estan "en el infinito", solo cuenta hacia donde mira la camara, no
//! donde esta. Durante el viaje rapido se estiran en rayas desde el centro.
const std = @import("std");
const rl = @import("raylib");

const Framebuffer = @import("framebuffer.zig").Framebuffer;
const View = @import("camera.zig").View;
const project = @import("camera.zig").project;
const Vec3 = rl.Vector3;

pub const COUNT = 1600;

const Star = struct {
    dir: Vec3,
    brightness: f32,
    tint: Vec3, // estrellas azuladas, blancas o anaranjadas
};

pub const Stars = struct {
    stars: [COUNT]Star,

    pub fn init(seed: u64) Stars {
        var prng = std.Random.DefaultPrng.init(seed);
        const rnd = prng.random();
        var s: Stars = undefined;
        for (&s.stars) |*st| {
            // Direccion uniforme sobre la esfera.
            const y = rnd.float(f32) * 2 - 1;
            const a = rnd.float(f32) * 2 * std.math.pi;
            const r = @sqrt(1 - y * y);
            st.dir = Vec3.init(r * @cos(a), y, r * @sin(a));
            const b = rnd.float(f32);
            st.brightness = 0.25 + 0.75 * b * b;
            const k = rnd.float(f32);
            st.tint = if (k < 0.25) Vec3.init(0.75, 0.85, 1.0) else if (k < 0.8) Vec3.init(1, 1, 1) else Vec3.init(1.0, 0.85, 0.65);
        }
        return s;
    }

    /// `warp` va de 0 (quieto) a 1 (maxima velocidad).
    pub fn draw(self: *const Stars, fb: *Framebuffer, view: *const View, time: f32, warp: f32) void {
        const w: f32 = @floatFromInt(fb.width);
        const h: f32 = @floatFromInt(fb.height);
        const cx = w / 2;
        const cy = h / 2;

        for (self.stars, 0..) |st, i| {
            // Solo importa la rotacion de la camara, no su posicion.
            const v = Vec3.init(st.dir.dotProduct(view.right), st.dir.dotProduct(view.up), st.dir.dotProduct(view.fwd));
            const p = project(view.*, v, w, h) orelse continue;

            const twinkle = 0.85 + 0.15 * @sin(time * 3 + @as(f32, @floatFromInt(i)));
            const lum = std.math.clamp(st.brightness * twinkle, 0, 1);
            const c = rl.Color.init(
                @intFromFloat(255 * lum * st.tint.x),
                @intFromFloat(255 * lum * st.tint.y),
                @intFromFloat(255 * lum * st.tint.z),
                255,
            );

            if (warp > 0.02) {
                // Raya: desde la estrella hacia afuera del centro de la pantalla.
                const ex = p[0] + (p[0] - cx) * warp * 0.45;
                const ey = p[1] + (p[1] - cy) * warp * 0.45;
                line(fb, p[0], p[1], ex, ey, c);
            } else {
                const x: i32 = @intFromFloat(p[0]);
                const y: i32 = @intFromFloat(p[1]);
                fb.put(x, y, c);
                if (st.brightness > 0.8) { // las mas brillantes se ven 2x2
                    fb.put(x + 1, y, c);
                    fb.put(x, y + 1, c);
                }
            }
        }
    }
};

/// Linea simple (DDA) en el framebuffer.
fn line(fb: *Framebuffer, x0: f32, y0: f32, x1: f32, y1: f32, c: rl.Color) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const steps: i32 = @intFromFloat(@min(300, @max(@abs(dx), @abs(dy))));
    if (steps <= 0) {
        fb.put(@intFromFloat(x0), @intFromFloat(y0), c);
        return;
    }
    const n: f32 = @floatFromInt(steps);
    var i: i32 = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / n;
        fb.put(@intFromFloat(x0 + dx * t), @intFromFloat(y0 + dy * t), c);
    }
}
