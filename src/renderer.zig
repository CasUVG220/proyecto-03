//! Dibuja los cuerpos celestes: escoge el nivel de detalle (LOD), aplica el
//! shader de vertices, y manda cada triangulo al rasterizador.
const std = @import("std");
const rl = @import("raylib");

const Framebuffer = @import("framebuffer.zig").Framebuffer;
const View = @import("camera.zig").View;
const lighting = @import("lighting.zig");
const mesh = @import("mesh.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");
const solar = @import("solar_system.zig");
const texture = @import("texture.zig");

const Vec3 = rl.Vector3;

/// Opciones que el usuario puede activar/desactivar para la demostracion.
pub const Settings = struct {
    cull_backfaces: bool = true,
    shadows: bool = true,
    force_low_lod: bool = false,
};

/// Tres versiones de la misma esfera: de muchos a pocos triangulos.
const LOD_SEGMENTS = [_][2]u32{ .{ 48, 24 }, .{ 24, 12 }, .{ 10, 6 } };

pub const Renderer = struct {
    lods: [3]mesh.Mesh,
    scratch: []Vec3, // vertices transformados del cuerpo que se esta dibujando
    tris_drawn: usize = 0, // estadistica del ultimo cuadro

    pub fn init(gpa: std.mem.Allocator) !Renderer {
        var r: Renderer = undefined;
        var made: usize = 0;
        errdefer for (r.lods[0..made]) |*m| m.deinit(gpa);
        for (LOD_SEGMENTS, 0..) |seg, i| {
            r.lods[i] = try mesh.sphere(gpa, seg[0], seg[1]);
            made += 1;
        }
        r.scratch = try gpa.alloc(Vec3, r.lods[0].verts.len);
        r.tris_drawn = 0;
        return r;
    }

    pub fn deinit(self: *Renderer, gpa: std.mem.Allocator) void {
        for (&self.lods) |*m| m.deinit(gpa);
        gpa.free(self.scratch);
    }

    /// LOD: mientras mas lejos (o mas chico se ve), menos triangulos.
    pub fn pickLod(self: *const Renderer, body: solar.Body, view: *const View, force_low: bool) usize {
        _ = self;
        if (force_low) return 2;
        const dist = body.pos.subtract(view.pos).length();
        const apparent = body.radius / @max(dist, 0.001); // tamano aparente
        if (apparent > 0.12) return 0;
        if (apparent > 0.04) return 1;
        return 2;
    }

    pub fn drawBodies(
        self: *Renderer,
        fb: *Framebuffer,
        view: *const View,
        bodies: []const solar.Body,
        textures: *const [texture.KIND_COUNT]texture.Texture,
        light: *const lighting.Light,
        time: f32,
        settings: Settings,
    ) void {
        self.tris_drawn = 0;
        for (bodies, 0..) |body, i| {
            // Descartar cuerpos completamente detras de la camara.
            const center_view = view.toView(body.pos);
            if (center_view.z < -body.radius * 1.2) continue;

            const lod_index = self.pickLod(body, view, settings.force_low_lod);
            const lod = &self.lods[lod_index];

            // Shader de vertices: mover cada vertice de la esfera unitaria.
            for (lod.verts, 0..) |dir, k| {
                const r = body.radius * shaders.vertexScale(body.shader, dir, time);
                self.scratch[k] = body.pos.add(dir.scale(r));
            }

            const shader = shaders.BodyShader{
                .body = &body,
                .index = i,
                .tex = &textures[@intFromEnum(body.texture)],
                .light = light,
                .cam_pos = view.pos,
                .time = time,
            };
            for (lod.tris) |t| {
                raster.drawTriangle(
                    fb,
                    view,
                    self.scratch[t.v[0]],
                    self.scratch[t.v[1]],
                    self.scratch[t.v[2]],
                    t.mat,
                    &shader,
                    .{ .cull_backfaces = settings.cull_backfaces },
                );
                self.tris_drawn += 1;
            }
        }
    }
};
