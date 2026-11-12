const std = @import("std");
const rl = @import("raylib");

const camera = @import("camera.zig");
const controls = @import("controls.zig");
const lighting = @import("lighting.zig");
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Renderer = @import("renderer.zig").Renderer;
const RenderSettings = @import("renderer.zig").Settings;
const solar = @import("solar_system.zig");
const Ship = @import("ship.zig").Ship;
const Stars = @import("stars.zig").Stars;
const textures_claude = @import("textures_claude.zig");
const Travel = @import("travel.zig").Travel;
const travel_mod = @import("travel.zig");

// El mundo se dibuja a baja resolucion y se escala con un factor entero:
// menos pixeles que calcular = mas FPS.
const RENDER_W: i32 = 640;
const RENDER_H: i32 = 360;
const SCALE: i32 = 2;
const ASPECT: f32 = @as(f32, RENDER_W) / @as(f32, RENDER_H);

/// Guarda el framebuffer actual como PNG (tecla F12, o `--shot archivo.png`).
fn saveShot(fb: *const Framebuffer, path: [:0]const u8) void {
    const img = rl.Image{
        .data = @ptrCast(fb.pixels.ptr),
        .width = fb.width,
        .height = fb.height,
        .mipmaps = 1,
        .format = .uncompressed_r8g8b8a8,
    };
    _ = rl.exportImage(img, path);
}

pub fn main(init: std.process.Init) !void {
    // Argumentos opcionales de desarrollo: --shot out.png [indice_destino]
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var shot_path: ?[:0]const u8 = null;
    var shot_target: ?usize = null;
    if (args.len > 2 and std.mem.eql(u8, args[1], "--shot")) {
        shot_path = args[2];
        if (args.len > 3) shot_target = std.fmt.parseInt(usize, args[3], 10) catch null;
    }

    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var fb = try Framebuffer.init(gpa, RENDER_W, RENDER_H);
    defer fb.deinit(gpa);

    var tex = try textures_claude.generateAll(gpa);
    defer for (&tex) |*t| t.deinit(gpa);

    var renderer = try Renderer.init(gpa);
    defer renderer.deinit(gpa);

    rl.setConfigFlags(.{ .vsync_hint = true });
    rl.initWindow(RENDER_W * SCALE, RENDER_H * SCALE, "Sistema Solar - Software Renderer");
    defer rl.closeWindow();
    rl.setTargetFPS(60);
    rl.disableCursor();

    // Textura de la pantalla: aqui subimos el framebuffer cada cuadro.
    const image = rl.genImageColor(RENDER_W, RENDER_H, rl.Color.black);
    const screen = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(screen);
    rl.unloadImage(image);
    const src = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(RENDER_W), .height = @floatFromInt(RENDER_H) };
    const dest = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(RENDER_W * SCALE), .height = @floatFromInt(RENDER_H * SCALE) };

    var bodies = solar.initBodies();
    const stars = Stars.init(2026);
    var cam = camera.Camera{ .pos = rl.Vector3.init(0, 70, 150), .fov = travel_mod.BASE_FOV };
    cam.lookAt(rl.Vector3.zero());
    var ship = try Ship.init(gpa, &cam);
    defer ship.deinit(gpa);
    var travel = Travel{};
    var settings = RenderSettings{};
    var occluders: [solar.COUNT]lighting.Occluder = undefined;

    var sim_time: f32 = if (shot_path != null) 20 else 0;
    var frames: u32 = 0;
    var paused = false;
    var title_timer: f32 = 0;
    var title_buf: [200:0]u8 = undefined;

    while (!rl.windowShouldClose()) {
        const dt = @min(rl.getFrameTime(), 0.05);
        frames += 1;
        if (shot_target) |t| {
            if (frames == 1) travel.start(&cam, t);
            if (frames == 2) travel.t = 0.999;
        }

        // ---- entrada ----
        if (rl.isKeyPressed(.p)) paused = !paused;
        if (rl.isKeyPressed(.b)) settings.cull_backfaces = !settings.cull_backfaces;
        if (rl.isKeyPressed(.v)) settings.shadows = !settings.shadows;
        if (rl.isKeyPressed(.l)) settings.force_low_lod = !settings.force_low_lod;
        if (rl.isKeyPressed(.tab)) travel.start(&cam, (travel.target + 1) % solar.COUNT);
        const keys = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight };
        for (keys, 0..) |k, i| {
            if (rl.isKeyPressed(k)) travel.start(&cam, i);
        }

        // ---- simulacion ----
        if (!paused) sim_time += dt;
        solar.update(&bodies, sim_time);
        if (travel.active) {
            travel.update(&cam, &bodies, dt);
        } else if (frames <= 2) {
            _ = rl.getMouseDelta(); // el primer delta del mouse es un salto falso
        } else if (shot_path == null) {
            controls.update(&cam, &bodies, dt);
        }

        // ---- render ----
        for (bodies, 0..) |b, i| {
            occluders[i] = .{ .center = b.pos, .radius = if (i == solar.SUN) 0 else b.radius, .id = i };
        }
        const light = lighting.Light{
            .pos = bodies[solar.SUN].pos,
            .radius = bodies[solar.SUN].radius,
            .occluders = &occluders,
            .shadows = settings.shadows,
        };
        ship.update(&cam, &bodies, dt);
        const view = cam.view(ASPECT);
        const moving = travel.active or rl.isKeyDown(.w) or rl.isKeyDown(.left_shift);

        const t_render = rl.getTime();
        fb.clear(rl.Color.init(3, 3, 10, 255));
        stars.draw(&fb, &view, sim_time, travel.warp());
        renderer.drawBodies(&fb, &view, &bodies, &tex, &light, sim_time, settings);
        ship.draw(&fb, &view, &light, sim_time, if (moving) 1 else 0.2, settings.cull_backfaces);

        if (shot_path != null) std.debug.print("render: {d:.2} ms, {d} tris\n", .{ (rl.getTime() - t_render) * 1000, renderer.tris_drawn });
        if (rl.isKeyPressed(.f12)) saveShot(&fb, "captura.png");
        if (shot_path) |p| {
            if (frames >= 6) {
                saveShot(&fb, p);
                break;
            }
        }
        rl.updateTexture(screen, @ptrCast(fb.pixels.ptr));
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.drawTexturePro(screen, src, dest, .{ .x = 0, .y = 0 }, 0, rl.Color.white);

        // Estado en el titulo de la ventana (no usamos funciones de dibujo de texto).
        title_timer += dt;
        if (title_timer > 0.4) {
            title_timer = 0;
            const title = std.fmt.bufPrintZ(&title_buf, "Sistema Solar | {d} FPS | {d} tris | destino: {s}{s}{s}{s}", .{
                rl.getFPS(),
                renderer.tris_drawn,
                bodies[travel.target].name,
                if (settings.cull_backfaces) "" else " | culling OFF",
                if (settings.shadows) "" else " | sombras OFF",
                if (settings.force_low_lod) " | LOD bajo" else "",
            }) catch "Sistema Solar";
            rl.setWindowTitle(title);
        }
    }
}
