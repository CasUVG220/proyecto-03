//! Cargador de archivos .obj. Soporta caras con CUALQUIER numero de vertices
//! (triangulos, quads, poligonos de n lados): cada cara se parte en un
//! abanico de triangulos. Tambien lee `usemtl` para saber el material de
//! cada cara.
const std = @import("std");
const rl = @import("raylib");

const mesh = @import("mesh.zig");

/// Lee un .obj desde texto. `material_names` lista los materiales conocidos:
/// el indice de cada uno es el numero que se guarda en `Tri.mat`.
pub fn parse(gpa: std.mem.Allocator, text: []const u8, material_names: []const []const u8) !mesh.Mesh {
    var verts: std.ArrayList(rl.Vector3) = .empty;
    errdefer verts.deinit(gpa);
    var tris: std.ArrayList(mesh.Tri) = .empty;
    errdefer tris.deinit(gpa);

    var current_mat: u8 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var tok = std.mem.tokenizeAny(u8, line, " \t");
        const kind = tok.next().?;

        if (std.mem.eql(u8, kind, "v")) {
            const x = try std.fmt.parseFloat(f32, tok.next() orelse return error.BadVertex);
            const y = try std.fmt.parseFloat(f32, tok.next() orelse return error.BadVertex);
            const z = try std.fmt.parseFloat(f32, tok.next() orelse return error.BadVertex);
            try verts.append(gpa, rl.Vector3.init(x, y, z));
        } else if (std.mem.eql(u8, kind, "usemtl")) {
            const name = tok.next() orelse "";
            current_mat = 0;
            for (material_names, 0..) |n, i| {
                if (std.mem.eql(u8, n, name)) current_mat = @intCast(i);
            }
        } else if (std.mem.eql(u8, kind, "f")) {
            // Indices de la cara (v, v/vt, v/vt/vn o v//vn); base 1 o negativos.
            var idx: [16]u32 = undefined;
            var n: usize = 0;
            while (tok.next()) |t| {
                if (n == idx.len) return error.FaceTooBig;
                const num = t[0 .. std.mem.indexOfScalar(u8, t, '/') orelse t.len];
                const i = try std.fmt.parseInt(i32, num, 10);
                const resolved: i64 = if (i < 0) @as(i64, @intCast(verts.items.len)) + i else i - 1;
                if (resolved < 0 or resolved >= verts.items.len) return error.BadIndex;
                idx[n] = @intCast(resolved);
                n += 1;
            }
            if (n < 3) return error.BadFace;
            // Abanico: (0,1,2), (0,2,3), (0,3,4)... conserva el sentido de giro.
            for (1..n - 1) |k| {
                try tris.append(gpa, .{ .v = .{ idx[0], idx[k], idx[k + 1] }, .mat = current_mat });
            }
        }
    }
    return .{ .verts = try verts.toOwnedSlice(gpa), .tris = try tris.toOwnedSlice(gpa) };
}

test "un quad se parte en 2 triangulos y un hexagono en 4" {
    const text =
        \\v 0 0 0
        \\v 1 0 0
        \\v 1 1 0
        \\v 0 1 0
        \\v 2 0 0
        \\v 2 1 0
        \\f 1 2 3 4
        \\f 1/1/1 2/2/2 3/3/3 4/4/4 5/5/5 6/6/6
    ;
    var m = try parse(std.testing.allocator, text, &.{});
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), m.tris.len);
    try std.testing.expectEqual(@as(usize, 6), m.verts.len);
}

test "usemtl asigna el material a las caras siguientes" {
    const text =
        \\v 0 0 0
        \\v 1 0 0
        \\v 0 1 0
        \\usemtl rojo
        \\f 1 2 3
        \\usemtl azul
        \\f 1 2 3
    ;
    var m = try parse(std.testing.allocator, text, &.{ "base", "rojo", "azul" });
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), m.tris[0].mat);
    try std.testing.expectEqual(@as(u8, 2), m.tris[1].mat);
}

test "indices negativos y caras invalidas" {
    var m = try parse(std.testing.allocator, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf -3 -2 -1\n", &.{});
    defer m.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), m.tris[0].v[0]);
    try std.testing.expectError(error.BadIndex, parse(std.testing.allocator, "v 0 0 0\nf 1 2 3\n", &.{}));
}

test "la nave de assets se carga: tiene quads y octagonos" {
    var m = try parse(std.testing.allocator, @embedFile("ship_obj"), &.{ "hull", "cockpit", "engine", "wing" });
    defer m.deinit(std.testing.allocator);
    // 40 quads * 2 + 4 octagonos * 6 = 104 triangulos.
    try std.testing.expectEqual(@as(usize, 104), m.tris.len);
}
