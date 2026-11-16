const std = @import("std");
const rl = @import("raylib");

const Camera = @import("camera.zig").Camera;
const solar = @import("solar_system.zig");
const Vec3 = rl.Vector3;

const LOOK_SPEED: f32 = 0.0022;
const KEY_LOOK_SPEED: f32 = 1.8;
const MOVE_SPEED: f32 = 16;
const BOOST: f32 = 4;
const CAM_RADIUS: f32 = 1.6;
const MAX_PITCH: f32 = 1.5;

pub fn update(cam: *Camera, bodies: []const solar.Body, dt: f32) void {
    const md = rl.getMouseDelta();
    cam.yaw += md.x * LOOK_SPEED;
    cam.pitch -= md.y * LOOK_SPEED;
    if (rl.isKeyDown(.left)) cam.yaw -= KEY_LOOK_SPEED * dt;
    if (rl.isKeyDown(.right)) cam.yaw += KEY_LOOK_SPEED * dt;
    if (rl.isKeyDown(.up)) cam.pitch += KEY_LOOK_SPEED * dt;
    if (rl.isKeyDown(.down)) cam.pitch -= KEY_LOOK_SPEED * dt;
    cam.pitch = std.math.clamp(cam.pitch, -MAX_PITCH, MAX_PITCH);

    const view = cam.view(1);
    var dir = Vec3.zero();
    if (rl.isKeyDown(.w)) dir = dir.add(view.fwd);
    if (rl.isKeyDown(.s)) dir = dir.subtract(view.fwd);
    if (rl.isKeyDown(.d)) dir = dir.add(view.right);
    if (rl.isKeyDown(.a)) dir = dir.subtract(view.right);
    if (rl.isKeyDown(.space)) dir = dir.add(Vec3.init(0, 1, 0));
    if (rl.isKeyDown(.left_control)) dir = dir.subtract(Vec3.init(0, 1, 0));

    if (dir.lengthSqr() > 0) {
        const speed = MOVE_SPEED * (if (rl.isKeyDown(.left_shift)) BOOST else 1);
        cam.pos = cam.pos.add(dir.normalize().scale(speed * dt));
    }

    cam.pos = solar.pushOut(bodies, cam.pos, CAM_RADIUS);
}
