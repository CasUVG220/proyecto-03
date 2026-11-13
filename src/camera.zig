const std = @import("std");
const rl = @import("raylib");

const Vec3 = rl.Vector3;
const WORLD_UP = Vec3.init(0, 1, 0);

pub const View = struct {
    pos: Vec3,
    right: Vec3,
    up: Vec3,
    fwd: Vec3,
    tan_half_fov: f32,
    aspect: f32,

    pub fn toView(self: View, p: Vec3) Vec3 {
        const d = p.subtract(self.pos);
        return Vec3.init(d.dotProduct(self.right), d.dotProduct(self.up), d.dotProduct(self.fwd));
    }
};

pub const Camera = struct {
    pos: Vec3,
    yaw: f32 = 0,
    pitch: f32 = 0,
    fov: f32 = 1.05,

    pub fn forward(self: Camera) Vec3 {
        return Vec3.init(
            @sin(self.yaw) * @cos(self.pitch),
            @sin(self.pitch),
            -@cos(self.yaw) * @cos(self.pitch),
        );
    }

    pub fn view(self: Camera, aspect: f32) View {
        const f = self.forward();
        const r = f.crossProduct(WORLD_UP).normalize();
        const u = r.crossProduct(f);
        return .{
            .pos = self.pos,
            .right = r,
            .up = u,
            .fwd = f,
            .tan_half_fov = @tan(self.fov / 2),
            .aspect = aspect,
        };
    }

    pub fn lookAt(self: *Camera, target: Vec3) void {
        const d = target.subtract(self.pos).normalize();
        self.pitch = std.math.asin(std.math.clamp(d.y, -1, 1));
        self.yaw = std.math.atan2(d.x, -d.z);
    }
};
