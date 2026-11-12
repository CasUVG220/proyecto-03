//! Datos del sistema solar: cada cuerpo, su orbita y su aspecto.
//! Las orbitas son circulos en el plano XZ; la luna orbita a la Tierra.
const std = @import("std");
const rl = @import("raylib");

const texture = @import("texture.zig");
const Vec3 = rl.Vector3;

/// Que shader usa cada cuerpo (ver shaders.zig).
pub const ShaderKind = enum { sun, rocky, venus, earth, jupiter, neptune };

pub const Body = struct {
    name: [:0]const u8,
    radius: f32,
    texture: texture.Kind,
    shader: ShaderKind,
    parent: ?usize = null, // indice del cuerpo al que orbita (null = fijo)
    orbit_radius: f32 = 0,
    orbit_speed: f32 = 0, // radianes por segundo
    phase: f32 = 0, // angulo inicial en la orbita
    spin_speed: f32 = 0, // rotacion sobre su eje, rad/s

    // Estado que cambia cada cuadro:
    pos: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    spin: f32 = 0,
};

pub const SUN: usize = 0;

pub const COUNT = 8;

pub fn initBodies() [COUNT]Body {
    return .{
        .{ .name = "Sol", .radius = 8, .texture = .sun, .shader = .sun, .spin_speed = 0.05 },
        .{ .name = "Mercurio", .radius = 1.0, .texture = .mercury, .shader = .rocky, .parent = 0, .orbit_radius = 18, .orbit_speed = 0.55, .phase = 0.5, .spin_speed = 0.3 },
        .{ .name = "Venus", .radius = 1.8, .texture = .venus, .shader = .venus, .parent = 0, .orbit_radius = 28, .orbit_speed = 0.40, .phase = 2.0, .spin_speed = -0.15 },
        .{ .name = "Tierra", .radius = 2.0, .texture = .earth, .shader = .earth, .parent = 0, .orbit_radius = 40, .orbit_speed = 0.30, .phase = 4.0, .spin_speed = 0.6 },
        .{ .name = "Luna", .radius = 0.5, .texture = .moon, .shader = .rocky, .parent = 3, .orbit_radius = 4.2, .orbit_speed = 1.4, .phase = 1.0, .spin_speed = 0.1 },
        .{ .name = "Marte", .radius = 1.4, .texture = .mars, .shader = .rocky, .parent = 0, .orbit_radius = 54, .orbit_speed = 0.24, .phase = 5.5, .spin_speed = 0.55 },
        .{ .name = "Jupiter", .radius = 4.5, .texture = .jupiter, .shader = .jupiter, .parent = 0, .orbit_radius = 78, .orbit_speed = 0.14, .phase = 3.0, .spin_speed = 1.0 },
        .{ .name = "Neptuno", .radius = 3.0, .texture = .neptune, .shader = .neptune, .parent = 0, .orbit_radius = 105, .orbit_speed = 0.09, .phase = 1.2, .spin_speed = 0.7 },
    };
}

/// Mueve todos los cuerpos a donde les toca en el tiempo `t` (segundos).
/// Los padres van antes que sus hijos en el arreglo, asi que ya tienen posicion.
pub fn update(bodies: []Body, t: f32) void {
    for (bodies) |*b| {
        b.spin = b.spin_speed * t;
        const center = if (b.parent) |p| bodies[p].pos else Vec3.zero();
        const a = b.phase + b.orbit_speed * t;
        b.pos = center.add(Vec3.init(@cos(a) * b.orbit_radius, 0, @sin(a) * b.orbit_radius));
    }
}

/// Colision: si `pos` (con un radio de `margin`) queda dentro de algun cuerpo,
/// lo empuja hacia afuera. Asi la camara y la nave nunca atraviesan planetas.
pub fn pushOut(bodies: []const Body, pos: Vec3, margin: f32) Vec3 {
    var p = pos;
    for (bodies) |b| {
        const d = p.subtract(b.pos);
        const dist = d.length();
        const min_dist = b.radius * 1.08 + margin;
        if (dist < min_dist) {
            const dir = if (dist > 1e-4) d.scale(1 / dist) else Vec3.init(0, 1, 0);
            p = b.pos.add(dir.scale(min_dist));
        }
    }
    return p;
}

test "la luna orbita a la tierra y no al sol" {
    var bodies = initBodies();
    update(&bodies, 10);
    const earth_moon = bodies[4].pos.subtract(bodies[3].pos).length();
    try std.testing.expectApproxEqAbs(bodies[4].orbit_radius, earth_moon, 0.001);
}

test "pushOut saca a la camara de un planeta" {
    var bodies = initBodies();
    update(&bodies, 0);
    const inside = bodies[3].pos.add(Vec3.init(0.5, 0, 0));
    const out = pushOut(&bodies, inside, 1.0);
    try std.testing.expect(out.subtract(bodies[3].pos).length() >= bodies[3].radius);
}
