//! Camara 3D libre (yaw + pitch) y la "vista" que usa el rasterizador.
const std = @import("std");
const rl = @import("raylib");

const Vec3 = rl.Vector3;
const WORLD_UP = Vec3.init(0, 1, 0);

/// Fotografia de la camara en un cuadro: posicion, ejes y parametros de lente.
pub const View = struct {
    pos: Vec3,
    right: Vec3,
    up: Vec3,
    fwd: Vec3,
    tan_half_fov: f32, // tan(fov/2), fov vertical
    aspect: f32, // ancho / alto

    /// Pasa un punto del mundo al espacio de la camara:
    /// x = derecha, y = arriba, z = hacia adelante (profundidad).
    pub fn toView(self: View, p: Vec3) Vec3 {
        const d = p.subtract(self.pos);
        return Vec3.init(d.dotProduct(self.right), d.dotProduct(self.up), d.dotProduct(self.fwd));
    }
};

pub const Camera = struct {
    pos: Vec3,
    yaw: f32 = 0, // 0 = mirando hacia -Z; positivo = gira a la derecha
    pitch: f32 = 0, // positivo = mira hacia arriba
    fov: f32 = 1.05, // ~60 grados

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

    /// Apunta la camara hacia un punto del mundo.
    pub fn lookAt(self: *Camera, target: Vec3) void {
        const d = target.subtract(self.pos).normalize();
        self.pitch = std.math.asin(std.math.clamp(d.y, -1, 1));
        self.yaw = std.math.atan2(d.x, -d.z);
    }
};
