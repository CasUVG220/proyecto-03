const std = @import("std");
const rl = @import("raylib");

const Camera = @import("camera.zig").Camera;
const lighting = @import("lighting.zig");
const solar = @import("solar_system.zig");
const Vec3 = rl.Vector3;

const DURATION: f32 = 2.2;
pub const BASE_FOV: f32 = 1.05;
const MAX_FOV_BOOST: f32 = 0.95;

pub const Travel = struct {
    active: bool = false,
    t: f32 = 0,
    target: usize = 0,
    from_pos: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    from_yaw: f32 = 0,
    from_pitch: f32 = 0,

    pub fn start(self: *Travel, cam: *const Camera, target: usize) void {
        self.* = .{ .active = true, .target = target, .from_pos = cam.pos, .from_yaw = cam.yaw, .from_pitch = cam.pitch };
    }

    pub fn warp(self: *const Travel) f32 {
        if (!self.active) return 0;
        return @sin(std.math.pi * self.t);
    }

    fn destination(bodies: []const solar.Body, target: usize) Vec3 {
        const b = bodies[target];
        const to_sun = bodies[solar.SUN].pos.subtract(b.pos);
        const dir = if (to_sun.length() > 0.01) to_sun.normalize() else Vec3.init(0, 0, 1);
        return b.pos.add(dir.scale(b.radius * 3.2 + 3)).add(Vec3.init(0, b.radius * 0.4, 0));
    }

    pub fn update(self: *Travel, cam: *Camera, bodies: []const solar.Body, dt: f32) void {
        if (!self.active) return;
        self.t = @min(1, self.t + dt / DURATION);
        const s = lighting.smoothstep(0, 1, self.t);

        cam.pos = self.from_pos.lerp(destination(bodies, self.target), s);

        var aim = cam.*;
        aim.lookAt(bodies[self.target].pos);
        cam.yaw = self.from_yaw + wrapAngle(aim.yaw - self.from_yaw) * s;
        cam.pitch = self.from_pitch + (aim.pitch - self.from_pitch) * s;

        cam.fov = BASE_FOV + MAX_FOV_BOOST * self.warp();
        if (self.t >= 1) {
            self.active = false;
            cam.fov = BASE_FOV;
        }
    }
};

fn wrapAngle(a: f32) f32 {
    var x = a;
    while (x > std.math.pi) x -= 2 * std.math.pi;
    while (x < -std.math.pi) x += 2 * std.math.pi;
    return x;
}
