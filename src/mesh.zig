//! Mallas de triangulos. Aqui vive la esfera unitaria con varios niveles de
//! detalle (LOD): la misma esfera con mas o menos triangulos.
const std = @import("std");
const rl = @import("raylib");

pub const Tri = struct {
    v: [3]u32, // indices en `verts`
    mat: u8 = 0, // material (lo usa la nave; las esferas ignoran esto)
};

pub const Mesh = struct {
    verts: []rl.Vector3,
    tris: []Tri,

    pub fn deinit(self: *Mesh, gpa: std.mem.Allocator) void {
        gpa.free(self.verts);
        gpa.free(self.tris);
    }
};

/// Esfera de radio 1: `segments` cortes en longitud y `rings` en latitud.
/// Los triangulos quedan en sentido antihorario visto desde afuera, que es
/// lo que necesita el back-face culling.
pub fn sphere(gpa: std.mem.Allocator, segments: u32, rings: u32) !Mesh {
    const verts = try gpa.alloc(rl.Vector3, (rings + 1) * segments);
    errdefer gpa.free(verts);

    for (0..rings + 1) |i| {
        const theta = std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rings));
        for (0..segments) |j| {
            const phi = 2 * std.math.pi * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(segments));
            verts[i * segments + j] = rl.Vector3.init(
                @sin(theta) * @cos(phi),
                @cos(theta),
                @sin(theta) * @sin(phi),
            );
        }
    }

    var tris: std.ArrayList(Tri) = .empty;
    errdefer tris.deinit(gpa);
    for (0..rings) |i| {
        for (0..segments) |j| {
            const j2 = (j + 1) % segments;
            const a: u32 = @intCast(i * segments + j);
            const b: u32 = @intCast(i * segments + j2);
            const c: u32 = @intCast((i + 1) * segments + j);
            const d: u32 = @intCast((i + 1) * segments + j2);
            // En los polos dos vertices coinciden: solo hay un triangulo.
            if (i != rings - 1) try tris.append(gpa, .{ .v = .{ b, d, c } });
            if (i != 0) try tris.append(gpa, .{ .v = .{ a, b, c } });
        }
    }
    return .{ .verts = verts, .tris = try tris.toOwnedSlice(gpa) };
}

test "los triangulos de la esfera miran hacia afuera" {
    var m = try sphere(std.testing.allocator, 12, 6);
    defer m.deinit(std.testing.allocator);
    for (m.tris) |t| {
        const a = m.verts[t.v[0]];
        const b = m.verts[t.v[1]];
        const c = m.verts[t.v[2]];
        const n = b.subtract(a).crossProduct(c.subtract(a));
        const center = a.add(b).add(c);
        try std.testing.expect(n.dotProduct(center) > 0);
    }
}

test "mas segmentos dan mas triangulos" {
    var lo = try sphere(std.testing.allocator, 8, 4);
    defer lo.deinit(std.testing.allocator);
    var hi = try sphere(std.testing.allocator, 32, 16);
    defer hi.deinit(std.testing.allocator);
    try std.testing.expect(hi.tris.len > lo.tris.len * 4);
}
