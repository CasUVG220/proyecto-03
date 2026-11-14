const std = @import("std");
const rl = @import("raylib");

const Vec3 = rl.Vector3;

pub const Occluder = struct {
    center: Vec3,
    radius: f32,
    id: usize,
};

pub const Light = struct {
    pos: Vec3,
    radius: f32,
    occluders: []const Occluder,
    shadows: bool = true,

    pub fn dirFrom(self: *const Light, p: Vec3) Vec3 {
        return self.pos.subtract(p).normalize();
    }

    pub fn intensityAt(self: *const Light, p: Vec3) f32 {
        const d = self.pos.subtract(p).length();
        const k = d / 70.0;
        return 1.8 / (1.0 + k * k);
    }

    pub fn shadowAt(self: *const Light, p: Vec3, self_id: usize) f32 {
        if (!self.shadows) return 1;
        const to_sun = self.pos.subtract(p);
        const dist_sun = to_sun.length();
        const l = to_sun.scale(1 / dist_sun);
        const sun_angle = self.radius / dist_sun;
        const penumbra = sun_angle * 0.6;

        var lit: f32 = 1;
        for (self.occluders) |o| {
            if (o.id == self_id) continue;
            const oc = o.center.subtract(p);
            const along = oc.dotProduct(l);
            if (along <= 0 or along >= dist_sun) continue;
            const d = oc.length();
            const occ_angle = o.radius / d;
            const off = oc.subtract(l.scale(along));
            const reach = (occ_angle + penumbra) * along;
            if (off.lengthSqr() > reach * reach) continue;
            const sep = off.length() / along;
            const cover = smoothstep(-penumbra, penumbra, occ_angle - sep);
            lit *= 1 - cover;
        }
        return lit;
    }
};

pub const AMBIENT = Vec3{ .x = 0.035, .y = 0.04, .z = 0.07 };
pub const SUN_COLOR = Vec3{ .x = 1.0, .y = 0.96, .z = 0.88 };

pub fn lambert(light: *const Light, base: Vec3, n: Vec3, p: Vec3, self_id: usize) Vec3 {
    const l = light.dirFrom(p);
    const ndl = @max(0, n.dotProduct(l));
    var direct: f32 = 0;
    if (ndl > 0) direct = ndl * light.shadowAt(p, self_id) * light.intensityAt(p);
    const lit = AMBIENT.add(SUN_COLOR.scale(direct));
    return base.multiply(lit);
}

pub fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = std.math.clamp((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
}

pub fn toColor(c: Vec3) rl.Color {
    return rl.Color.init(
        @intFromFloat(std.math.clamp(c.x, 0, 1) * 255),
        @intFromFloat(std.math.clamp(c.y, 0, 1) * 255),
        @intFromFloat(std.math.clamp(c.z, 0, 1) * 255),
        255,
    );
}

test "un cuerpo entre el punto y el Sol da sombra, uno al lado no" {
    const occ = [_]Occluder{.{ .center = Vec3.init(10, 0, 0), .radius = 2, .id = 1 }};
    const light = Light{ .pos = Vec3.init(100, 0, 0), .radius = 5, .occluders = &occ };
    try std.testing.expect(light.shadowAt(Vec3.init(0, 0, 0), 0) < 0.05);
    try std.testing.expectEqual(@as(f32, 1), light.shadowAt(Vec3.init(0, 20, 0), 0));
    try std.testing.expectEqual(@as(f32, 1), light.shadowAt(Vec3.init(0, 0, 0), 1));
}

test "el Sol ilumina menos al alejarse" {
    const light = Light{ .pos = Vec3.zero(), .radius = 5, .occluders = &.{} };
    try std.testing.expect(light.intensityAt(Vec3.init(20, 0, 0)) > light.intensityAt(Vec3.init(100, 0, 0)));
}
