const std = @import("std");
const rl = @import("raylib");

const Camera = @import("camera.zig").Camera;
const View = @import("camera.zig").View;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const lighting = @import("lighting.zig");
const mesh = @import("mesh.zig");
const obj = @import("obj.zig");
const raster = @import("raster.zig");
const solar = @import("solar_system.zig");

const Vec3 = rl.Vector3;

const MATERIALS = [_][]const u8{ "hull", "cockpit", "engine", "wing" };
const COLORS = [_]Vec3{
    Vec3{ .x = 0.72, .y = 0.74, .z = 0.80 },
    Vec3{ .x = 0.25, .y = 0.55, .z = 0.95 },
    Vec3{ .x = 1.00, .y = 0.50, .z = 0.12 },
    Vec3{ .x = 0.85, .y = 0.22, .z = 0.16 },
};

const SCALE: f32 = 1.2;
const DISTANCE: f32 = 5.0;
const DROP: f32 = 1.1;
const FOLLOW_RATE: f32 = 7.0;
const SHIP_RADIUS: f32 = 1.2;

pub const Ship = struct {
    model: mesh.Mesh,
    scratch: []Vec3,
    yaw: f32,
    pitch: f32,
    roll: f32 = 0,
    pos: Vec3 = .{ .x = 0, .y = 0, .z = 0 },

    pub fn init(gpa: std.mem.Allocator, cam: *const Camera) !Ship {
        const model = try obj.parse(gpa, @embedFile("ship_obj"), &MATERIALS);
        return .{
            .model = model,
            .scratch = try gpa.alloc(Vec3, model.verts.len),
            .yaw = cam.yaw,
            .pitch = cam.pitch,
        };
    }

    pub fn deinit(self: *Ship, gpa: std.mem.Allocator) void {
        self.model.deinit(gpa);
        gpa.free(self.scratch);
    }

    fn basis(self: *const Ship) struct { fwd: Vec3, right: Vec3, up: Vec3 } {
        const cam = Camera{ .pos = Vec3.zero(), .yaw = self.yaw, .pitch = self.pitch };
        const v = cam.view(1);
        const c = @cos(self.roll);
        const s = @sin(self.roll);
        return .{
            .fwd = v.fwd,
            .right = v.right.scale(c).add(v.up.scale(s)),
            .up = v.up.scale(c).subtract(v.right.scale(s)),
        };
    }

    pub fn update(self: *Ship, cam: *const Camera, bodies: []const solar.Body, dt: f32) void {
        const k = 1 - @exp(-FOLLOW_RATE * dt);
        const dyaw = angleDiff(cam.yaw, self.yaw);
        self.yaw += dyaw * k;
        self.pitch += (cam.pitch - self.pitch) * k;
        const target_roll = std.math.clamp(dyaw * 2.5, -0.7, 0.7);
        self.roll += (target_roll - self.roll) * k;

        const v = cam.view(1);
        const lateral = std.math.clamp(-dyaw * 3, -1.5, 1.5);
        const p = cam.pos.add(v.fwd.scale(DISTANCE)).add(v.up.scale(-DROP)).add(v.right.scale(lateral));
        self.pos = solar.pushOut(bodies, p, SHIP_RADIUS);
    }

    pub fn draw(
        self: *Ship,
        fb: *Framebuffer,
        view: *const View,
        light: *const lighting.Light,
        time: f32,
        thrust: f32,
        cull: bool,
    ) void {
        const b = self.basis();
        for (self.model.verts, 0..) |v, i| {
            self.scratch[i] = self.pos
                .add(b.right.scale(v.x * SCALE))
                .add(b.fwd.scale(v.y * SCALE))
                .add(b.up.scale(v.z * SCALE));
        }
        const shader = ShipShader{ .light = light, .time = time, .thrust = thrust };
        for (self.model.tris) |t| {
            raster.drawTriangle(fb, view, self.scratch[t.v[0]], self.scratch[t.v[1]], self.scratch[t.v[2]], t.mat, &shader, .{ .cull_backfaces = cull });
        }
    }
};

const ShipShader = struct {
    light: *const lighting.Light,
    time: f32,
    thrust: f32,

    pub fn shade(self: *const ShipShader, f: raster.Fragment) ?raster.Shaded {
        const base = COLORS[@min(f.material, COLORS.len - 1)];
        var c = lighting.lambert(self.light, base, f.normal, f.world, 9999);
        c = c.add(base.scale(0.32));
        if (f.material == 2) {
            const flicker = 0.85 + 0.15 * @sin(self.time * 30);
            c = base.scale((0.7 + 0.8 * self.thrust) * flicker);
        }
        return .{ .color = lighting.toColor(c) };
    }
};

fn angleDiff(a: f32, b: f32) f32 {
    var d = a - b;
    while (d > std.math.pi) d -= 2 * std.math.pi;
    while (d < -std.math.pi) d += 2 * std.math.pi;
    return d;
}
