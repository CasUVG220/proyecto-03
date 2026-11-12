const std = @import("std");
const rl = @import("raylib");

const Framebuffer = @import("framebuffer.zig").Framebuffer;

// El mundo se dibuja a baja resolucion y se escala con un factor entero:
// menos pixeles que calcular = mas FPS.
const RENDER_W: i32 = 480;
const RENDER_H: i32 = 270;
const SCALE: i32 = 3;

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var fb = try Framebuffer.init(gpa, RENDER_W, RENDER_H);
    defer fb.deinit(gpa);

    rl.setConfigFlags(.{ .vsync_hint = true });
    rl.initWindow(RENDER_W * SCALE, RENDER_H * SCALE, "Sistema Solar - Software Renderer");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Textura de la pantalla: aqui subimos el framebuffer cada cuadro.
    const image = rl.genImageColor(RENDER_W, RENDER_H, rl.Color.black);
    const screen = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(screen);
    rl.unloadImage(image);

    const src = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(RENDER_W), .height = @floatFromInt(RENDER_H) };
    const dest = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(RENDER_W * SCALE), .height = @floatFromInt(RENDER_H * SCALE) };

    while (!rl.windowShouldClose()) {
        fb.clear(rl.Color.init(4, 4, 12, 255));
        // (aqui se renderiza la escena)

        rl.updateTexture(screen, @ptrCast(fb.pixels.ptr));
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.drawTexturePro(screen, src, dest, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    }
}
