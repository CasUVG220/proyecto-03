//! Shaders de los cuerpos celestes. Hay dos tipos:
//!   - vertexScale: modifica la GEOMETRIA (el radio cambia segun el punto y el tiempo)
//!   - BodyShader.shade: decide el COLOR de cada pixel
//! Cada planeta tiene su propia funcion; casi todos hacen algo especial.
const std = @import("std");
const rl = @import("raylib");

const lighting = @import("lighting.zig");
const raster = @import("raster.zig");
const solar = @import("solar_system.zig");
const texture = @import("texture.zig");

const Vec3 = rl.Vector3;
const Body = solar.Body;
const smoothstep = lighting.smoothstep;

/// Shader de vertices: factor que multiplica el radio en la direccion `dir`.
/// Neptuno "respira" con ondas; el Sol palpita.
pub fn vertexScale(kind: solar.ShaderKind, dir: Vec3, time: f32) f32 {
    const lon = std.math.atan2(dir.z, dir.x);
    switch (kind) {
        .neptune => return 1 + 0.05 * @sin(lon * 5 + time * 2.0) * @sin(dir.y * 4 + time),
        .sun => return 1 + 0.012 * @sin(time * 3),
        else => return 1,
    }
}

pub const BodyShader = struct {
    body: *const Body,
    index: usize,
    tex: *const texture.Texture,
    light: *const lighting.Light,
    cam_pos: Vec3,
    time: f32,

    pub fn shade(self: *const BodyShader, f: raster.Fragment) ?raster.Shaded {
        // En una esfera la normal es la direccion desde el centro.
        const n = f.world.subtract(self.body.pos).normalize();
        // Direccion "local": la normal girada al reves de la rotacion del planeta,
        // asi la textura gira con el planeta.
        const local = rotY(n, -self.body.spin);
        const color = switch (self.body.shader) {
            .sun => self.sun(n, local),
            .rocky => self.rocky(n, local, f.world),
            .venus => self.venus(n, local, f.world),
            .earth => self.earth(n, local, f.world),
            .jupiter => self.jupiter(n, local, f.world),
            .neptune => self.rocky(n, local, f.world),
        };
        return .{ .color = lighting.toColor(color) };
    }

    /// Sol: no recibe luz, emite. Dos capas de plasma que se mueven en sentidos
    /// opuestos, y el borde se oscurece un poco (limb darkening).
    fn sun(self: *const BodyShader, n: Vec3, local: Vec3) Vec3 {
        const uv = texture.dirToUv(local);
        const t = self.time;
        const a = self.tex.sample(uv[0] + t * 0.02, uv[1]).rgb;
        const b = self.tex.sample(uv[0] * 1.0 - t * 0.035 + 0.3, 1 - uv[1]).rgb;
        const plasma = a.lerp(b, 0.5).scale(1.35 + 0.1 * @sin(t * 2));
        const to_cam = self.cam_pos.subtract(self.body.pos).normalize();
        const facing = @max(0, n.dotProduct(to_cam));
        return plasma.scale(0.55 + 0.45 * facing);
    }

    /// Mercurio, Luna, Marte: textura + luz del Sol.
    fn rocky(self: *const BodyShader, n: Vec3, local: Vec3, p: Vec3) Vec3 {
        const base = self.tex.sampleDir(local).rgb;
        return lighting.lambert(self.light, base, n, p, self.index);
    }

    /// Venus: las nubes se arremolinan con el tiempo y una atmosfera brilla en el borde.
    fn venus(self: *const BodyShader, n: Vec3, local: Vec3, p: Vec3) Vec3 {
        const uv = texture.dirToUv(local);
        const t = self.time;
        const swirl = 0.015 * @sin(uv[1] * 40 + t * 0.7);
        const base = self.tex.sample(uv[0] + t * 0.012 + swirl, uv[1]).rgb;
        var c = lighting.lambert(self.light, base, n, p, self.index);
        const to_cam = self.cam_pos.subtract(p).normalize();
        const rim = std.math.pow(f32, 1 - @max(0, n.dotProduct(to_cam)), 3);
        const day = @max(0, n.dotProduct(self.light.dirFrom(p)));
        c = c.add(Vec3.init(1.0, 0.75, 0.35).scale(rim * 0.6 * (0.2 + day)));
        return c;
    }

    /// Tierra: el mar brilla con reflejo (especular) y el lado nocturno
    /// enciende luces de ciudades.
    fn earth(self: *const BodyShader, n: Vec3, local: Vec3, p: Vec3) Vec3 {
        const s = self.tex.sampleDir(local);
        var c = lighting.lambert(self.light, s.rgb, n, p, self.index);
        const l = self.light.dirFrom(p);
        const ndl = n.dotProduct(l);

        if (s.mask < 0.5 and ndl > 0) {
            // Reflejo del Sol en el oceano (Blinn-Phong).
            const v = self.cam_pos.subtract(p).normalize();
            const h = l.add(v).normalize();
            const spec = std.math.pow(f32, @max(0, n.dotProduct(h)), 60);
            c = c.add(Vec3.init(1, 0.95, 0.85).scale(spec * 0.8 * self.light.shadowAt(p, self.index)));
        }
        if (s.mask > 0.5) {
            // Ciudades: puntos de luz solo en tierra firme y de noche.
            const uv = texture.dirToUv(local);
            const cell = hash2(@intFromFloat(uv[0] * 300), @intFromFloat(uv[1] * 150));
            const night = 1 - smoothstep(-0.12, 0.1, ndl);
            if (cell > 0.9) c = c.add(Vec3.init(1.0, 0.8, 0.4).scale(night * 0.9));
        }
        return c;
    }

    /// Jupiter: las bandas se desplazan a distinta velocidad segun la latitud.
    fn jupiter(self: *const BodyShader, n: Vec3, local: Vec3, p: Vec3) Vec3 {
        const uv = texture.dirToUv(local);
        const shift = 0.02 * @sin(self.time * 0.25 + uv[1] * 18) + self.time * 0.004;
        const base = self.tex.sample(uv[0] + shift, uv[1]).rgb;
        return lighting.lambert(self.light, base, n, p, self.index);
    }
};

fn rotY(v: Vec3, ang: f32) Vec3 {
    const c = @cos(ang);
    const s = @sin(ang);
    return Vec3.init(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

fn hash2(x: i32, y: i32) f32 {
    var h: u32 = @as(u32, @bitCast(x)) *% 374761393 +% @as(u32, @bitCast(y)) *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xFFFF)) / 65535.0;
}

test "neptuno deforma la geometria y la luna no" {
    const d = Vec3.init(1, 0, 0);
    try std.testing.expect(vertexScale(.neptune, d, 0.4) != 1);
    try std.testing.expectEqual(@as(f32, 1), vertexScale(.rocky, d, 0.4));
}
