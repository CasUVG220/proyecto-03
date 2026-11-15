const std = @import("std");
const rl = @import("raylib");

const Framebuffer = @import("framebuffer.zig").Framebuffer;
const View = @import("camera.zig").View;
const Vec3 = rl.Vector3;

const NEAR: f32 = 0.1;
const EDGE_EPS: f32 = 1e-4;

pub const Fragment = struct {
    world: Vec3,
    depth: f32,
    normal: Vec3,
    material: u8,
};

pub const Shaded = struct {
    color: rl.Color,
    alpha: f32 = 1,
};

pub const Options = struct {
    cull_backfaces: bool = true,
};

const Vert = struct { view: Vec3, world: Vec3 };

fn lerpVert(a: Vert, b: Vert, t: f32) Vert {
    return .{ .view = a.view.lerp(b.view, t), .world = a.world.lerp(b.world, t) };
}

pub fn drawTriangle(
    fb: *Framebuffer,
    view: *const View,
    wa: Vec3,
    wb: Vec3,
    wc: Vec3,
    material: u8,
    shader: anytype,
    opts: Options,
) void {
    const v = [3]Vert{
        .{ .view = view.toView(wa), .world = wa },
        .{ .view = view.toView(wb), .world = wb },
        .{ .view = view.toView(wc), .world = wc },
    };

    var poly: [4]Vert = undefined;
    var n: usize = 0;
    for (0..3) |i| {
        const cur = v[i];
        const nxt = v[(i + 1) % 3];
        const cur_in = cur.view.z >= NEAR;
        const nxt_in = nxt.view.z >= NEAR;
        if (cur_in) {
            poly[n] = cur;
            n += 1;
        }
        if (cur_in != nxt_in) {
            poly[n] = lerpVert(cur, nxt, (NEAR - cur.view.z) / (nxt.view.z - cur.view.z));
            n += 1;
        }
    }
    if (n < 3) return;
    for (1..n - 1) |i| {
        fillTriangle(fb, view, poly[0], poly[i], poly[i + 1], material, shader, opts);
    }
}

fn fillTriangle(
    fb: *Framebuffer,
    view: *const View,
    a: Vert,
    b: Vert,
    c: Vert,
    material: u8,
    shader: anytype,
    opts: Options,
) void {
    const w: f32 = @floatFromInt(fb.width);
    const h: f32 = @floatFromInt(fb.height);

    const sx = [3]f32{ screenX(a.view, view, w), screenX(b.view, view, w), screenX(c.view, view, w) };
    const sy = [3]f32{ screenY(a.view, view, h), screenY(b.view, view, h), screenY(c.view, view, h) };

    const area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
    if (area == 0) return;
    const back_facing = area > 0;
    if (opts.cull_backfaces and back_facing) return;

    var normal = b.world.subtract(a.world).crossProduct(c.world.subtract(a.world)).normalize();
    if (back_facing) normal = normal.negate();

    const min_x = @max(0, @floor(@min(sx[0], @min(sx[1], sx[2]))));
    const max_x = @min(w - 1, @ceil(@max(sx[0], @max(sx[1], sx[2]))));
    const min_y = @max(0, @floor(@min(sy[0], @min(sy[1], sy[2]))));
    const max_y = @min(h - 1, @ceil(@max(sy[0], @max(sy[1], sy[2]))));
    if (min_x > max_x or min_y > max_y) return;

    const inv_z = [3]f32{ 1 / a.view.z, 1 / b.view.z, 1 / c.view.z };
    const inv_area = 1 / area;

    var y: i32 = @intFromFloat(min_y);
    const y_end: i32 = @intFromFloat(max_y);
    while (y <= y_end) : (y += 1) {
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        var x: i32 = @intFromFloat(min_x);
        const x_end: i32 = @intFromFloat(max_x);
        while (x <= x_end) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const l0 = ((sx[1] - px) * (sy[2] - py) - (sx[2] - px) * (sy[1] - py)) * inv_area;
            const l1 = ((sx[2] - px) * (sy[0] - py) - (sx[0] - px) * (sy[2] - py)) * inv_area;
            const l2 = 1 - l0 - l1;
            if (l0 < -EDGE_EPS or l1 < -EDGE_EPS or l2 < -EDGE_EPS) continue;

            const iz = l0 * inv_z[0] + l1 * inv_z[1] + l2 * inv_z[2];
            const z = 1 / iz;
            const idx: usize = @intCast(y * fb.width + x);
            if (z >= fb.depth[idx]) continue;

            const p0 = l0 * inv_z[0] * z;
            const p1 = l1 * inv_z[1] * z;
            const p2 = l2 * inv_z[2] * z;
            const world = a.world.scale(p0).add(b.world.scale(p1)).add(c.world.scale(p2));

            const shaded = shader.shade(.{
                .world = world,
                .depth = z,
                .normal = normal,
                .material = material,
            }) orelse continue;

            if (shaded.alpha >= 1) {
                fb.pixels[idx] = shaded.color;
                fb.depth[idx] = z;
            } else {
                const dst = fb.pixels[idx];
                const t = shaded.alpha;
                fb.pixels[idx] = rl.Color.init(
                    mix(dst.r, shaded.color.r, t),
                    mix(dst.g, shaded.color.g, t),
                    mix(dst.b, shaded.color.b, t),
                    255,
                );
            }
        }
    }
}

fn mix(a: u8, b: u8, t: f32) u8 {
    const f = @as(f32, @floatFromInt(a)) * (1 - t) + @as(f32, @floatFromInt(b)) * t;
    return @intFromFloat(std.math.clamp(f, 0, 255));
}

fn screenX(p: Vec3, view: *const View, w: f32) f32 {
    return (p.x / (p.z * view.tan_half_fov * view.aspect) * 0.5 + 0.5) * w;
}

fn screenY(p: Vec3, view: *const View, h: f32) f32 {
    return (0.5 - p.y / (p.z * view.tan_half_fov) * 0.5) * h;
}

const SolidShader = struct {
    pub fn shade(_: *const SolidShader, _: Fragment) ?Shaded {
        return .{ .color = rl.Color.white };
    }
};

fn countWhite(fb: *const Framebuffer) usize {
    var n: usize = 0;
    for (fb.pixels) |p| {
        if (p.r == 255) n += 1;
    }
    return n;
}

fn testView() View {
    return .{
        .pos = Vec3.init(0, 0, 0),
        .right = Vec3.init(1, 0, 0),
        .up = Vec3.init(0, 1, 0),
        .fwd = Vec3.init(0, 0, -1),
        .tan_half_fov = 0.6,
        .aspect = 1,
    };
}

test "un triangulo de frente se dibuja y de espaldas se descarta" {
    var fb = try Framebuffer.init(std.testing.allocator, 32, 32);
    defer fb.deinit(std.testing.allocator);
    const view = testView();
    const shader = SolidShader{};

    fb.clear(rl.Color.black);
    drawTriangle(&fb, &view, Vec3.init(-1, -1, -3), Vec3.init(1, -1, -3), Vec3.init(0, 1, -3), 0, &shader, .{});
    try std.testing.expect(countWhite(&fb) > 20);

    fb.clear(rl.Color.black);
    drawTriangle(&fb, &view, Vec3.init(1, -1, -3), Vec3.init(-1, -1, -3), Vec3.init(0, 1, -3), 0, &shader, .{});
    try std.testing.expectEqual(@as(usize, 0), countWhite(&fb));

    fb.clear(rl.Color.black);
    drawTriangle(&fb, &view, Vec3.init(1, -1, -3), Vec3.init(-1, -1, -3), Vec3.init(0, 1, -3), 0, &shader, .{ .cull_backfaces = false });
    try std.testing.expect(countWhite(&fb) > 20);
}

test "un triangulo que cruza el plano cercano no revienta" {
    var fb = try Framebuffer.init(std.testing.allocator, 32, 32);
    defer fb.deinit(std.testing.allocator);
    const view = testView();
    const shader = SolidShader{};
    fb.clear(rl.Color.black);
    drawTriangle(&fb, &view, Vec3.init(-2, -1, -3), Vec3.init(2, -1, -3), Vec3.init(0, 6, 5), 0, &shader, .{ .cull_backfaces = false });
    try std.testing.expect(countWhite(&fb) > 0);
}
