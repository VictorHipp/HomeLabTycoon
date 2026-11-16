"""Generate the low-poly prototype models (style "Taller luminoso", docs/ART_STYLE.md).

Usage (from the project root):
  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup \
      --python tools/blender/build_prototype_models.py -- --root . [--only switch_16p_1u,server_1u_entry]

Outputs per model:
  assets/models/<category>/<id>.glb   (imported by Godot)
  art_source/<category>/<id>.blend    (editable source, modifiers kept live)

Conventions (docs/ART_STYLE.md §8):
  * 1 Blender unit = 1 m. Blender is Z-up; the glTF exporter writes Y-up.
  * Object front faces Blender -Y  (= +Z in Godot).
  * Functional empties: PORT_<group>_<i>, LED_<name>, POWER_IN_<n>, POWER_OUT_<n>,
    STAND_POINT, CAM_<mode>, RACK_U1, SCREEN (mesh).
  * Port / power empties: their -Y axis points out of the socket (Godot +Z).
  * CAM_* and STAND_POINT empties: look / face along their +Y axis (Godot -Z, like Camera3D).
  * Rack-mounted devices: origin = bottom centre of the front face of the rack ears.
  * Floor / furniture objects: origin = bottom centre.
"""
import argparse
import math
import os
import random
import sys
import zlib

import bmesh
import bpy
from mathutils import Vector

U = 0.04445            # 1U [VERIFICADO: EIA-310 via Wikipedia "19-inch rack", 2026-11-15]
PANEL_W = 0.4826       # 19" front panel width (same source)
OPENING_W = 0.45085    # width between posts (same source)
HOLE_SPACING = 0.465   # horizontal hole centre spacing 464.2-465.8 mm (same source)

# ---------------------------------------------------------------- palette ---
# sRGB hex values from docs/ART_STYLE.md §4 (+ a few prop colours marked "extra").
MATERIALS = {
    "tinta": {"color": "#1E2430", "rough": 0.7},
    "grafito": {"color": "#2E3440", "rough": 0.65},
    "acero": {"color": "#5C6675", "rough": 0.45, "metal": 0.5},
    "niebla": {"color": "#C9D1D9", "rough": 0.7},
    "hueso": {"color": "#EFE6D8", "rough": 0.85},
    "madera": {"color": "#C98F5A", "rough": 0.8},
    "madera_oscura": {"color": "#B07A4A", "rough": 0.8},      # extra: second floor tone
    "terracota": {"color": "#C8654A", "rough": 0.85},
    "mostaza": {"color": "#E0B34A", "rough": 0.7},
    "salvia": {"color": "#8FAF8B", "rough": 0.85},
    "beige_retro": {"color": "#D6C7A6", "rough": 0.75},       # extra: old PC plastic
    "carton": {"color": "#B98A5E", "rough": 0.95},            # extra: package
    "cinta": {"color": "#9C7046", "rough": 0.6},              # extra: packing tape
    "piel": {"color": "#E2AE8A", "rough": 0.8},               # extra: mannequin skin
    "pelo": {"color": "#3B2A20", "rough": 0.9},               # extra: mannequin hair
    "salvia_oscura": {"color": "#6E8C6A", "rough": 0.85},     # extra: jacket collar and cuffs
    "vaquero": {"color": "#4A5770", "rough": 0.9},            # extra: jeans (muted, not cable blue)
    "vaquero_claro": {"color": "#66748C", "rough": 0.9},      # extra: rolled-up jeans hem
    "cuero": {"color": "#6B4A32", "rough": 0.7},              # extra: belt
    "castano": {"color": "#5E4331", "rough": 0.9},            # extra: character hair and beard
    "puerto": {"color": "#101318", "rough": 0.9},             # socket interiors
    "cable_cobre": {"color": "#3B82C4", "rough": 0.6},
    "cristal": {"color": "#BFE3F2", "rough": 0.1, "alpha": 0.35},
    "cielo": {"color": "#CFE8F5", "rough": 1.0, "emit": 1.2},  # window backdrop
    "pantalla": {"color": "#1B3A5C", "rough": 0.3, "emit": 0.6},
    "led_ok": {"color": "#4ADE80", "rough": 0.3, "emit": 6.0},
    "led_act": {"color": "#F5A524", "rough": 0.3, "emit": 6.0},
    "led_fallo": {"color": "#EF4444", "rough": 0.3, "emit": 6.0},
    "led_id": {"color": "#60A5FA", "rough": 0.3, "emit": 6.0},
    "led_off": {"color": "#2A2F38", "rough": 0.4},
}
_MAT_CACHE: dict = {}


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgba(hex_color: str, alpha: float = 1.0):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), alpha)


def mat(name: str):
    m = _MAT_CACHE.get(name)
    if m is not None and m.name in bpy.data.materials:
        return m
    spec = MATERIALS[name]
    m = bpy.data.materials.new("M_" + name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    alpha = spec.get("alpha", 1.0)
    bsdf.inputs["Base Color"].default_value = _rgba(spec["color"])
    bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.8)
    bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    if "emit" in spec:
        bsdf.inputs["Emission Color"].default_value = _rgba(spec["color"])
        bsdf.inputs["Emission Strength"].default_value = spec["emit"]
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = _rgba(spec["color"], alpha)
    _MAT_CACHE[name] = m
    return m


# --------------------------------------------------------------- builders ---
def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def box(name, size, loc, material, chamfer=0.0, rot=(0.0, 0.0, 0.0)):
    """Axis-aligned box. `chamfer` = bevel width as a fraction of the smallest side."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(me)
    bm.free()
    ob = _link(bpy.data.objects.new(name, me))
    ob.location = loc
    ob.rotation_euler = rot
    me.materials.append(mat(material))
    if chamfer > 0.0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = chamfer * min(size)
        mod.segments = 1
        mod.limit_method = "ANGLE"
    return ob


def cylinder(name, radius, depth, loc, material, segments=12, rot=(0.0, 0.0, 0.0), chamfer=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=depth)
    bm.to_mesh(me)
    bm.free()
    ob = _link(bpy.data.objects.new(name, me))
    ob.location = loc
    ob.rotation_euler = rot
    me.materials.append(mat(material))
    if chamfer > 0.0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = chamfer * min(radius * 2, depth)
        mod.segments = 1
        mod.limit_method = "ANGLE"
    return ob


def sphere(name, radius, loc, material, segments=12, rings=8, scale=(1.0, 1.0, 1.0)):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bm.to_mesh(me)
    bm.free()
    ob = _link(bpy.data.objects.new(name, me))
    ob.location = loc
    ob.scale = scale
    me.materials.append(mat(material))
    return ob


RJ45_W, RJ45_H, RJ45_NOTCH_W, RJ45_NOTCH_H = 0.0118, 0.0092, 0.006, 0.0022


def _rj45_prism(bm, depth):
    """Closed T-shaped prism (socket opening + latch notch on top), centred on the origin,
    extruded along Y. Returns its vertices."""
    w, h, nw, nh = RJ45_W, RJ45_H, RJ45_NOTCH_W, RJ45_NOTCH_H
    outline = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (nw / 2, h / 2),
               (nw / 2, h / 2 + nh), (-nw / 2, h / 2 + nh), (-nw / 2, h / 2), (-w / 2, h / 2)]
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in outline]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in outline]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        faces.append(bm.faces.new((front[i], front[j], back[j], back[i])))
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return front + back


def cut(target, holes, material, kind="box"):
    """Boolean-difference a set of holes out of `target`.

    holes: list of (size_or_radius_depth, world_location[, rotation]) tuples.
    The new faces take the cutter material (dark socket interiors).
    """
    me = bpy.data.meshes.new(target.name + "_cutter")
    bm = bmesh.new()
    for hole in holes:
        dims, loc = hole[0], hole[1]
        rot = hole[2] if len(hole) > 2 else None
        if kind == "box":
            geom = bmesh.ops.create_cube(bm, size=1.0)
            verts = geom["verts"]
            for v in verts:
                v.co = Vector((v.co.x * dims[0], v.co.y * dims[1], v.co.z * dims[2]))
        elif kind == "rj45":
            verts = _rj45_prism(bm, depth=0.008)
        else:  # cylinder: dims = (radius, depth)
            geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16,
                                         radius1=dims[0], radius2=dims[0], depth=dims[1])
            verts = geom["verts"]
        if rot is not None:
            from mathutils import Euler
            mtx = Euler(rot).to_matrix()
            for v in verts:
                v.co = mtx @ v.co
        for v in verts:
            v.co += Vector(loc)
    bm.to_mesh(me)
    bm.free()
    cutter = _link(bpy.data.objects.new(target.name + "_cutter", me))
    me.materials.append(mat(material))
    cutter.hide_render = True
    cutter.display_type = "WIRE"      # keep it evaluated (hide_viewport would disable the operand)
    cutter["is_cutter"] = True
    mod = target.modifiers.new("Holes", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    try:
        mod.solver = "MANIFOLD"
    except Exception:
        mod.solver = "EXACT"
    return cutter


def empty(name, loc, rot=(0.0, 0.0, 0.0), size=0.02):
    ob = _link(bpy.data.objects.new(name, None))
    ob.empty_display_type = "ARROWS"
    ob.empty_display_size = size
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def look_rot(from_pos, to_pos):
    """Euler for a CAM_ empty at from_pos whose +Y axis looks at to_pos."""
    d = Vector(to_pos) - Vector(from_pos)
    yaw = math.atan2(-d.x, d.y)                     # rotate +Y towards the target in XY
    pitch = math.atan2(d.z, math.hypot(d.x, d.y))   # tilt +Y up/down
    return (pitch, 0.0, yaw)


OUT = math.pi  # rotation that turns an empty's -Y towards Blender +Y (rear faces)


# ----------------------------------------------------------- rack helpers ---
def rack_ears(depth_front, height, material="acero"):
    """Two 19" ears at the front plane (y in [0, 0.003])."""
    ear_w = (PANEL_W - 0.440) / 2
    for side in (-1, 1):
        ear = box(f"ear_{'l' if side < 0 else 'r'}", (ear_w, 0.003, height),
                  (side * (0.220 + ear_w / 2), 0.0015, height / 2), material, chamfer=0.1)
        cut(ear, [((0.007, 0.02, 0.005), (side * HOLE_SPACING / 2, 0.0015, height / 2))], "puerto")


def rj45_ports(group, plate, positions, y_face, outward_rot=(0.0, 0.0, 0.0), led_materials=None,
               led_side=1):
    """Carve RJ45 sockets into `plate` and add PORT_ empties (+ optional link LEDs).

    positions: list of (x, z) socket centres. y_face: y of the plate's outer face.
    """
    w, h = RJ45_W, RJ45_H
    inward = 1.0 if outward_rot == (0.0, 0.0, 0.0) else -1.0   # direction into the device
    # One T-shaped prism per socket (no overlapping cutters: the boolean needs a clean
    # manifold operand). Cutters start 2 mm outside the face and go 6 mm in.
    holes = [(None, (x, y_face + inward * 0.002, z)) for x, z in positions]
    cut(plate, holes, "puerto", kind="rj45")
    for i, (x, z) in enumerate(positions):
        empty(f"PORT_{group}_{i}", (x, y_face - inward * 0.0005, z), outward_rot)
        if led_materials is not None:
            box(f"LED_{group}_{i}", (0.0024, 0.0012, 0.0024),
                (x + led_side * (w / 2 + 0.0022), y_face - inward * 0.0005, z + h / 2 - 0.0012),
                led_materials[i % len(led_materials)] if callable(led_materials) is False else led_materials(i))


def power_inlet(name, target, center, y_face, outward_rot=(0.0, 0.0, 0.0)):
    """IEC C14-style inlet: dark rectangular recess + POWER_IN_ empty."""
    inward = 1.0 if outward_rot == (0.0, 0.0, 0.0) else -1.0
    cut(target, [((0.026, 0.012, 0.018), (center[0], y_face + inward * 0.005, center[1]))], "puerto")
    empty(name, (center[0], y_face - inward * 0.0005, center[1]), outward_rot)


# ----------------------------------------------------------------- models ---
def build_switch_16p_1u():
    """Linkara LS-16G: 1U, 16 x RJ45 1 Gbps, unmanaged. Front at y=0."""
    h, depth = U - 0.0008, 0.22
    body = box("chassis", (0.440, depth, h), (0, 0.003 + depth / 2, h / 2), "grafito", chamfer=0.08)
    face = box("faceplate", (0.440, 0.004, h), (0, 0.002, h / 2), "acero", chamfer=0.05)
    rack_ears(0.0, h)
    # 2 rows x 8 columns; real switches number the top row odd, the bottom row even.
    positions = []
    for col in range(8):
        for row in range(2):
            positions.append((0.030 + col * 0.0175 + 0.0059, h * 0.68 if row == 0 else h * 0.30))
    lit = {0: "led_ok", 1: "led_ok", 2: "led_act", 4: "led_ok"}   # showcase pattern only
    rj45_ports("lan", face, positions, y_face=0.0, led_materials=lambda i: lit.get(i, "led_off"))
    # status area (left)
    box("LED_power", (0.004, 0.0012, 0.004), (-0.190, -0.0005, h * 0.62), "led_ok")
    box("LED_system", (0.004, 0.0012, 0.004), (-0.180, -0.0005, h * 0.62), "led_ok")
    box("label", (0.060, 0.0008, 0.012), (-0.120, -0.0004, h * 0.5), "niebla", chamfer=0.1)
    box("logo", (0.008, 0.0009, 0.008), (-0.160, -0.0004, h * 0.5), "mostaza")
    power_inlet("POWER_IN_1", body, (-0.150, h / 2), y_face=0.003 + depth, outward_rot=(0, 0, OUT))


def build_server_1u_entry():
    """Nodex NX-1: 1U entry server. Front bezel light, rear: 2 x RJ45 + PSU inlet."""
    h, depth = U - 0.0008, 0.50
    body = box("chassis", (0.440, depth, h), (0, 0.003 + depth / 2, h / 2), "grafito", chamfer=0.08)
    bezel = box("bezel", (0.440, 0.006, h), (0, 0.003, h / 2), "niebla", chamfer=0.12)
    rack_ears(0.0, h)
    bays = [(-0.135 + i * 0.075, h * 0.48) for i in range(4)]
    cut(bezel, [((0.066, 0.01, 0.020), (x, 0.0, z)) for x, z in bays], "puerto")
    for i, (x, z) in enumerate(bays):
        box(f"bay_tray_{i}", (0.060, 0.003, 0.016), (x, 0.002, z), "tinta", chamfer=0.1)
        box(f"bay_handle_{i}", (0.012, 0.002, 0.004), (x + 0.020, -0.0005, z), "mostaza")
        box(f"LED_drive_{i}", (0.003, 0.0012, 0.003), (x - 0.025, -0.0005, z + 0.006), "led_ok")
    cylinder("power_button", 0.0045, 0.003, (0.180, -0.001, h / 2), "acero", rot=(math.pi / 2, 0, 0))
    box("LED_power", (0.0035, 0.0012, 0.0035), (0.195, -0.0005, h * 0.66), "led_ok")
    box("LED_id", (0.0035, 0.0012, 0.0035), (0.195, -0.0005, h * 0.34), "led_id")
    # rear
    rear_y = 0.003 + depth
    rj45_ports("lan", body, [(0.020, h / 2), (0.040, h / 2)], y_face=rear_y, outward_rot=(0, 0, OUT),
               led_materials=lambda i: "led_ok", led_side=-1)
    power_inlet("POWER_IN_1", body, (-0.170, h / 2), y_face=rear_y, outward_rot=(0, 0, OUT))
    cut(body, [((0.004, 0.012, 0.022), (0.090 + i * 0.008, rear_y, h / 2)) for i in range(12)], "puerto")


def build_rack_12u_open():
    """Rackwell RW-12: open four-post floor rack, 12U. Origin: bottom centre of footprint."""
    units, depth, post = 12, 0.60, 0.040
    base_h, top_h = 0.075, 0.050
    usable = units * U
    height = base_h + usable + top_h
    y_front = -depth / 2 + post          # front face of the front posts' mounting plane
    post_x = OPENING_W / 2 + post / 2    # inner edge of posts at the 450.85 mm opening
    for sx in (-1, 1):
        for sy, yc in (("f", -depth / 2 + post / 2), ("r", depth / 2 - post / 2)):
            box(f"post_{sy}{'l' if sx < 0 else 'r'}", (post, post, height), (sx * post_x, yc, height / 2),
                "acero", chamfer=0.08)
        box(f"base_side_{'l' if sx < 0 else 'r'}", (post, depth, post), (sx * post_x, 0, post / 2), "acero", chamfer=0.08)
        box(f"top_side_{'l' if sx < 0 else 'r'}", (post, depth, post), (sx * post_x, 0, height - post / 2), "acero", chamfer=0.08)
        for sy in (-1, 1):
            cylinder(f"foot_{sx}_{sy}", 0.018, 0.012, (sx * post_x, sy * (depth / 2 - post / 2), 0.006),
                     "tinta", segments=10)
    for sy, yc in (("f", -depth / 2 + post / 2), ("r", depth / 2 - post / 2)):
        box(f"base_cross_{sy}", (OPENING_W, post, post), (0, yc, post / 2), "acero", chamfer=0.08)
        box(f"top_cross_{sy}", (OPENING_W, post, post), (0, yc, height - post / 2), "acero", chamfer=0.08)
    # U ticks on the front face of both front posts (readability in close-up)
    for u in range(units + 1):
        z = base_h + u * U
        for sx in (-1, 1):
            box(f"u_tick_{'l' if sx < 0 else 'r'}_{u}", (0.010, 0.0012, 0.0016),
                (sx * (OPENING_W / 2 + 0.006), -depth / 2 - 0.0006, z), "niebla")
    # Functional markers
    empty("RACK_U1", (0, -depth / 2 - 0.003, base_h))   # front mounting plane minus ear thickness
    stand = (0, -depth / 2 - 0.70, 0)
    empty("STAND_POINT", stand)                         # faces +Y (the rack): identity
    target = (0, -depth / 2, base_h + usable / 2)
    cam_f = (0, -depth / 2 - 0.80, 0.95)
    empty("CAM_rack_front", cam_f, look_rot(cam_f, target))
    cam_r = (0, depth / 2 + 0.80, 0.95)
    empty("CAM_rack_rear", cam_r, look_rot(cam_r, (0, depth / 2, base_h + usable / 2)))


def build_router_home():
    """Linkara Home R4: desktop router, 4 LAN + 1 WAN, 2 antennas."""
    w, d, h = 0.22, 0.15, 0.038
    body = box("body", (w, d, h), (0, 0, h / 2), "niebla", chamfer=0.25)
    leds = ["led_ok", "led_ok", "led_ok", "led_ok", "led_act", "led_off", "led_off"]
    names = ["power", "internet", "wifi", "lan_0", "lan_1", "lan_2", "lan_3"]
    for i, (n, m) in enumerate(zip(names, leds)):
        box(f"LED_{n}", (0.004, 0.0015, 0.004), (-0.045 + i * 0.015, -d / 2 - 0.0004, h * 0.55), m)
    rj45_ports("lan", body, [(-0.055 + i * 0.019, h * 0.45) for i in range(4)], y_face=d / 2,
               outward_rot=(0, 0, OUT))
    rj45_ports("wan", body, [(0.040, h * 0.45)], y_face=d / 2, outward_rot=(0, 0, OUT))
    box("wan_mark", (0.014, 0.001, 0.0022), (0.040, d / 2 + 0.0004, h * 0.45 - 0.0078), "mostaza")
    cut(body, [((0.004, 0.01, 0.004), (0.080, d / 2, h * 0.45))], "puerto")
    empty("POWER_IN_1", (0.080, d / 2 + 0.0005, h * 0.45), (0, 0, OUT))
    for sx in (-1, 1):
        cylinder(f"antenna_{sx}", 0.006, 0.17, (sx * 0.09, d / 2 - 0.01, h + 0.08), "tinta", segments=8,
                 rot=(math.radians(-8), math.radians(10 * sx), 0), chamfer=0.3)


def build_power_strip_4():
    """4-way domestic power strip with rocker switch. Sockets on the top face."""
    w, d, h = 0.30, 0.055, 0.040
    body = box("body", (w, d, h), (0, 0, h / 2), "hueso", chamfer=0.25)
    xs = [-0.075 + i * 0.05 for i in range(4)]
    cut(body, [((0.017, 0.012), (x, 0, h)) for x in xs], "puerto", kind="cyl")
    for i, x in enumerate(xs):
        empty(f"POWER_OUT_{i + 1}", (x, 0, h + 0.0005), (-math.pi / 2, 0, 0))
    box("switch", (0.018, 0.028, 0.008), (0.125, 0, h + 0.003), "terracota", chamfer=0.2)
    box("LED_power", (0.004, 0.004, 0.002), (0.125, -0.008, h + 0.0075), "led_fallo")
    cylinder("cord", 0.004, 0.15, (-w / 2 - 0.075, 0, 0.006), "tinta", segments=8, rot=(0, math.pi / 2, 0))


def build_pc_tower_old():
    """Old beige tower PC. Front: optical bay, power button, LEDs. Rear: RJ45 + PSU."""
    w, d, h = 0.18, 0.42, 0.40
    body = box("case", (w, d, h), (0, 0, h / 2), "beige_retro", chamfer=0.06)
    cut(body, [((0.15, 0.01, 0.042), (0, -d / 2, h - 0.06))], "puerto")
    box("optical_tray", (0.146, 0.004, 0.038), (0, -d / 2 + 0.002, h - 0.06), "beige_retro", chamfer=0.1)
    cylinder("power_button", 0.012, 0.006, (0, -d / 2 - 0.002, h - 0.16), "terracota", segments=16,
             rot=(math.pi / 2, 0, 0), chamfer=0.2)
    box("LED_power", (0.005, 0.0015, 0.005), (-0.03, -d / 2 - 0.0005, h - 0.16), "led_ok")
    box("LED_disk", (0.005, 0.0015, 0.005), (0.03, -d / 2 - 0.0005, h - 0.16), "led_act")
    for i in range(6):
        box(f"vent_{i}", (0.12, 0.002, 0.004), (0, -d / 2 - 0.0008, 0.06 + i * 0.012), "grafito")
    rj45_ports("lan", body, [(0.040, h * 0.55)], y_face=d / 2, outward_rot=(0, 0, OUT),
               led_materials=lambda i: "led_ok", led_side=-1)
    power_inlet("POWER_IN_1", body, (-0.040, h - 0.05), y_face=d / 2, outward_rot=(0, 0, OUT))


def build_monitor_old():
    """19" LCD monitor on a stand. The screen mesh is named SCREEN (ViewportTexture later)."""
    sw, sh = 0.40, 0.31
    base_h, neck_h = 0.018, 0.10
    box("base", (0.22, 0.16, base_h), (0, 0, base_h / 2), "tinta", chamfer=0.3)
    box("neck", (0.05, 0.03, neck_h), (0, 0.03, base_h + neck_h / 2), "tinta", chamfer=0.2)
    zc = base_h + neck_h + sh / 2 + 0.02
    frame = box("frame", (sw + 0.03, 0.045, sh + 0.03), (0, 0.0, zc), "tinta", chamfer=0.1)
    cut(frame, [((sw, 0.02, sh), (0, -0.0225, zc))], "puerto")
    box("SCREEN", (sw, 0.002, sh), (0, -0.0135, zc), "pantalla")
    box("LED_power", (0.004, 0.0015, 0.003), (sw / 2 - 0.01, -0.023, zc - sh / 2 - 0.008), "led_id")
    cam = (0, -0.55, zc)
    empty("CAM_screen", cam, look_rot(cam, (0, 0, zc)))


def build_keyboard_mouse():
    box("keyboard", (0.44, 0.14, 0.022), (0, 0, 0.011), "tinta", chamfer=0.25)
    box("keys", (0.41, 0.115, 0.006), (0, -0.002, 0.024), "niebla", chamfer=0.3)
    for r in range(4):
        box(f"key_gap_{r}", (0.41, 0.002, 0.0025), (0, -0.045 + r * 0.03, 0.0272), "grafito")
    box("mouse", (0.06, 0.10, 0.03), (0.30, 0.0, 0.015), "tinta", chamfer=0.45)


def build_desk():
    w, d, top_z = 1.20, 0.60, 0.75
    box("top", (w, d, 0.03), (0, 0, top_z - 0.015), "madera", chamfer=0.3)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"leg_{sx}_{sy}", (0.045, 0.045, top_z - 0.03), (sx * (w / 2 - 0.05), sy * (d / 2 - 0.05),
                (top_z - 0.03) / 2), "grafito", chamfer=0.1)
    box("drawers", (0.40, 0.50, 0.55), (w / 2 - 0.25, 0.02, 0.30), "salvia", chamfer=0.04)
    for i in range(3):
        box(f"handle_{i}", (0.10, 0.012, 0.012), (w / 2 - 0.25, -0.235, 0.47 - i * 0.16), "mostaza", chamfer=0.2)
    empty("STAND_POINT", (-0.15, -d / 2 - 0.45, 0))


def build_chair():
    """Swivel office chair; its front (where the knees go) faces -Y (Godot +Z). SEAT = top of the
    seat, where the hips of a seated character go (slightly towards the backrest)."""
    empty("SEAT", (0, 0.04, 0.505))
    box("seat", (0.46, 0.46, 0.07), (0, 0, 0.47), "salvia", chamfer=0.3)
    box("back", (0.44, 0.06, 0.42), (0, 0.22, 0.75), "salvia", chamfer=0.3, rot=(math.radians(-8), 0, 0))
    cylinder("column", 0.025, 0.36, (0, 0, 0.25), "grafito", segments=10)
    for i in range(5):
        a = i * 2 * math.pi / 5
        box(f"spoke_{i}", (0.30, 0.04, 0.03), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.06), "grafito",
            chamfer=0.2, rot=(0, 0, a))
        sphere(f"caster_{i}", 0.025, (math.cos(a) * 0.29, math.sin(a) * 0.29, 0.025), "tinta", segments=8, rings=6)


def build_bed():
    box("frame", (0.98, 2.04, 0.26), (0, 0, 0.13), "madera", chamfer=0.12)
    box("headboard", (0.98, 0.06, 0.80), (0, 1.0, 0.40), "madera", chamfer=0.2)
    box("mattress", (0.92, 1.96, 0.18), (0, -0.01, 0.35), "hueso", chamfer=0.35)
    box("blanket", (0.96, 1.30, 0.06), (0, -0.33, 0.45), "terracota", chamfer=0.4)
    box("pillow", (0.60, 0.32, 0.12), (0, 0.78, 0.49), "niebla", chamfer=0.5)


def build_cabinet_small():
    box("body", (0.50, 0.36, 0.52), (0, 0, 0.26), "salvia", chamfer=0.05)
    box("top", (0.54, 0.40, 0.03), (0, 0, 0.535), "madera", chamfer=0.3)
    box("door_line", (0.002, 0.003, 0.44), (0, -0.181, 0.27), "grafito")
    for sx in (-1, 1):
        box(f"knob_{sx}", (0.015, 0.012, 0.015), (sx * 0.03, -0.186, 0.38), "mostaza", chamfer=0.3)


def build_rug():
    box("rug", (1.70, 1.10, 0.012), (0, 0, 0.006), "mostaza", chamfer=0.2)
    box("rug_inner", (1.50, 0.90, 0.0125), (0, 0, 0.0065), "terracota", chamfer=0.2)


def build_package_box():
    w, d, h = 0.50, 0.40, 0.34
    box("box", (w, d, h), (0, 0, h / 2), "carton", chamfer=0.03)
    box("tape_top", (0.06, d + 0.002, 0.002), (0, 0, h + 0.0005), "cinta")
    box("tape_front", (0.06, 0.002, 0.12), (0, -d / 2 - 0.0005, h - 0.06), "cinta")
    box("label", (0.14, 0.002, 0.09), (0.12, -d / 2 - 0.0008, h * 0.45), "hueso", chamfer=0.1)
    empty("STAND_POINT", (0, -d / 2 - 0.55, 0))


def parent_keep(child, parent):
    """Parent without moving the child in world space."""
    bpy.context.view_layer.update()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def build_room_bedroom():
    """3.5 x 3.0 m bedroom shell. Floor top at z=0. Back wall at +Y, left wall at -X.
    Every wall exists twice (docs/CAMERA_SYSTEM.md §3.3, decision 15):
      WALL_<side>      full height; window / door parts are its children,
      WALL_<side>_cut  empty grouping the low (0.30 m) version.
    The game shows one or the other depending on where the camera is."""
    W, D, H, T, LOW = 3.5, 3.0, 2.6, 0.10, 0.30
    planks = 14
    pw = W / planks
    for i in range(planks):
        box(f"floor_plank_{i}", (pw, D, 0.04), (-W / 2 + pw * (i + 0.5), 0, -0.02),
            "madera" if i % 2 == 0 else "madera_oscura", chamfer=0.06)
    door_y, door_w = -1.02, 0.80          # near the camera-side corner, clear of the bed
    children = {"back": [], "left": []}

    # Back wall with the window.
    back = box("WALL_back", (W + 2 * T, T, H), (0, D / 2 + T / 2, H / 2), "hueso")
    cut(back, [((1.10, 0.3, 1.10), (0.55, D / 2 + T / 2, 1.45))], "niebla")
    children["back"] += [
        box("window_frame_top", (1.16, 0.14, 0.05), (0.55, D / 2 + T / 2, 2.025), "niebla", chamfer=0.2),
        box("window_frame_bottom", (1.24, 0.20, 0.05), (0.55, D / 2 + T / 2 - 0.03, 0.875), "niebla", chamfer=0.2),
        box("window_mullion", (0.035, 0.10, 1.10), (0.55, D / 2 + T / 2, 1.45), "niebla"),
        box("window_glass", (1.10, 0.01, 1.10), (0.55, D / 2 + T / 2, 1.45), "cristal"),
        box("window_sky", (1.6, 0.02, 1.6), (0.55, D / 2 + T + 0.25, 1.45), "cielo"),
    ]
    for sx in (-1, 1):
        children["back"].append(box(f"window_frame_side_{sx}", (0.05, 0.14, 1.10),
                                    (0.55 + sx * 0.575, D / 2 + T / 2, 1.45), "niebla", chamfer=0.2))
    # Left wall with the door.
    left = box("WALL_left", (T, D, H), (-W / 2 - T / 2, 0, H / 2), "hueso")
    cut(left, [((0.3, door_w, 2.08), (-W / 2 - T / 2, door_y, 1.04))], "madera")
    for sy in (-1, 1):
        children["left"].append(box(f"door_frame_{sy}", (0.14, 0.05, 2.12),
                                    (-W / 2 - T / 2, door_y + sy * (door_w / 2 + 0.025), 1.06), "madera", chamfer=0.2))
    children["left"] += [
        box("door_frame_top", (0.14, door_w + 0.10, 0.05), (-W / 2 - T / 2, door_y, 2.105), "madera", chamfer=0.2),
        box("door", (0.04, door_w - 0.02, 2.06), (-W / 2 - T / 2 + 0.03, door_y, 1.03), "madera_oscura", chamfer=0.15),
        cylinder("door_handle", 0.012, 0.08, (-W / 2 + 0.03, door_y + 0.30, 1.0), "acero", rot=(0, math.pi / 2, 0)),
    ]
    # Plain full-height front and right walls.
    box("WALL_front", (W + 2 * T, T, H), (0, -D / 2 - T / 2, H / 2), "hueso")
    box("WALL_right", (T, D, H), (W / 2 + T / 2, 0, H / 2), "hueso")
    for side in ("back", "left"):
        wall = bpy.data.objects[f"WALL_{side}"]
        for child in children[side]:
            parent_keep(child, wall)

    # Low (cut) versions, each grouped under an empty WALL_<side>_cut.
    def low_wall(side, segments):
        group = empty(f"WALL_{side}_cut", (0, 0, 0), size=0.1)
        for i, (size, loc) in enumerate(segments):
            seg = box(f"wall_{side}_low_{i}", (size[0], size[1], LOW), (loc[0], loc[1], LOW / 2), "hueso", chamfer=0.1)
            cap = box(f"wall_{side}_cap_{i}", (size[0] + 0.004, size[1] + 0.01, 0.02), (loc[0], loc[1], LOW + 0.01), "grafito")
            parent_keep(seg, group)
            parent_keep(cap, group)

    low_wall("back", [((W + 2 * T, T), (0, D / 2 + T / 2))])
    low_wall("front", [((W + 2 * T, T), (0, -D / 2 - T / 2))])
    low_wall("right", [((T, D), (W / 2 + T / 2, 0))])
    gap_lo, gap_hi = door_y - door_w / 2 - 0.05, door_y + door_w / 2 + 0.05
    low_wall("left", [((T, gap_lo + D / 2), (-W / 2 - T / 2, (gap_lo - D / 2) / 2)),
                      ((T, D / 2 - gap_hi), (-W / 2 - T / 2, (gap_hi + D / 2) / 2))])
    # skirting boards (always visible)
    box("skirting_back", (W, 0.015, 0.08), (0, D / 2 - 0.0075, 0.04), "terracota")
    box("skirting_left", (0.015, D, 0.08), (-W / 2 + 0.0075, 0, 0.04), "terracota")
    box("skirting_front", (W, 0.015, 0.08), (0, -D / 2 + 0.0075, 0.04), "terracota")
    box("skirting_right", (0.015, D, 0.08), (W / 2 - 0.0075, 0, 0.04), "terracota")
    # Centre of the reserved delivery zone (sim/world/bedroom_scenario.gd DELIVERY_ZONE), inside the
    # entrance against the front wall, right of the door (Godot x -0.65, z 1.20).
    empty("DELIVERY_POINT", (-0.65, -1.20, 0))


def build_mannequin():
    """Scale mannequin (~1.75 m), NOT the final character: proportions reference only.
    Articulated for the procedural animation (game/character/character_animator.gd): every limb
    hangs from an empty placed on its joint (J_hip / J_knee / J_ankle, J_shoulder / J_elbow,
    suffix _L / _R), so rotating the empty in Godot bends the limb at the right place.
    Standing: hips at 0.84 m, knees at 0.44 m, ankles at 0.07 m, shoulders at 1.35 m."""
    for sx, side in ((-1, "L"), (1, "R")):
        x = sx * 0.085
        hip = empty(f"J_hip_{side}", (x, 0, 0.84), size=0.05)
        knee = empty(f"J_knee_{side}", (x, 0, 0.44), size=0.05)
        ankle = empty(f"J_ankle_{side}", (x, 0, 0.07), size=0.05)
        parent_keep(box(f"thigh_{sx}", (0.13, 0.15, 0.41), (x, 0, 0.64), "tinta", chamfer=0.3), hip)
        parent_keep(box(f"shin_{sx}", (0.12, 0.14, 0.39), (x, 0, 0.255), "tinta", chamfer=0.3), knee)
        parent_keep(box(f"shoe_{sx}", (0.13, 0.24, 0.07), (x, -0.03, 0.035), "grafito", chamfer=0.4), ankle)
        parent_keep(ankle, knee)
        parent_keep(knee, hip)
        ax = sx * 0.265
        shoulder = empty(f"J_shoulder_{side}", (ax, 0, 1.35), size=0.05)
        elbow = empty(f"J_elbow_{side}", (ax, 0, 1.08), size=0.05)
        parent_keep(box(f"upperarm_{sx}", (0.095, 0.11, 0.28), (ax, 0, 1.215), "salvia", chamfer=0.4), shoulder)
        parent_keep(box(f"forearm_{sx}", (0.09, 0.105, 0.26), (ax, 0, 0.95), "salvia", chamfer=0.4), elbow)
        parent_keep(sphere(f"hand_{sx}", 0.055, (sx * 0.27, 0, 0.79), "piel", segments=10, rings=7), elbow)
        parent_keep(elbow, shoulder)
    box("torso", (0.44, 0.25, 0.60), (0, 0, 1.12), "salvia", chamfer=0.35)
    cylinder("neck", 0.055, 0.08, (0, 0, 1.45), "piel", segments=10)
    sphere("head", 0.145, (0, 0, 1.60), "piel", segments=14, rings=10, scale=(1.0, 0.95, 1.05))
    sphere("hair", 0.152, (0, 0.02, 1.64), "pelo", segments=14, rings=10, scale=(1.03, 1.0, 0.85))
    for sx in (-1, 1):
        sphere(f"eye_{sx}", 0.018, (sx * 0.05, -0.135, 1.60), "tinta", segments=8, rings=6)


# ------------------------------------------------------ faceted character ---
# The player character (user request 2026-11-16): faceted low-poly modelling, flat shaded, every
# triangle painted with one of three tones of its colour (fixed seeds: the .glb is reproducible).
# Same joints as the mannequin, so CharacterAnimator and its tests apply unchanged.
TONES = (1.0, 0.87, 1.09)   # sRGB factor of each tone (0 = the palette colour)
TONE_ODDS = (0.56, 0.24)    # chance of tone 0 and tone 1; tone 2 takes the rest


def _rng(name):
    return random.Random(zlib.crc32(name.encode("utf-8")))


def tone_mat(name, tone):
    """Palette material `name`, darkened or lightened by TONES[tone]."""
    if tone == 0:
        return mat(name)
    key = f"{name}_t{tone}"
    if key not in MATERIALS:
        spec = dict(MATERIALS[name])
        h = spec["color"].lstrip("#")
        rgb = [min(255, round(int(h[i:i + 2], 16) * TONES[tone])) for i in (0, 2, 4)]
        spec["color"] = "#%02X%02X%02X" % tuple(rgb)
        MATERIALS[key] = spec
    return mat(key)


def _finish(name, bm, material, tones=True):
    """Object from a closed bmesh (vertices in world space): outward normals, triangulated,
    flat shaded and, with `tones`, each triangle in one of the tones of `material`."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    rng = _rng(name)
    for f in bm.faces:
        f.smooth = False
        if tones:
            r = rng.random()
            f.material_index = 0 if r < TONE_ODDS[0] else (1 if r < TONE_ODDS[0] + TONE_ODDS[1] else 2)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = _link(bpy.data.objects.new(name, me))
    for t in range(3 if tones else 1):
        me.materials.append(tone_mat(material, t))
    return ob


def _axis_point(axis, t, u, v):
    if axis == "z":
        return Vector((u, v, t))
    if axis == "y":
        return Vector((u, t, v))
    return Vector((t, u, v))


def _ring_points(ring, sides, axis, a0=None, a1=None, shrink=0.0, jitter=0.0, rng=None):
    """One cross-section. ring = (t, cu, cv, ru, rv[, ex]): superellipse of radii ru, rv
    (exponent ex: 2 = ellipse, higher = boxier) centred on (cu, cv), at t along `axis`.
    Angle -pi/2 points to -v (the front for a vertical loft). Closed ring of `sides` points
    (a face, not an edge, looks to the front), or the open arc a0..a1 (sides + 1 points)."""
    t, cu, cv, ru, rv = ring[:5]
    ex = ring[5] if len(ring) > 5 else 2.0
    ru, rv = max(ru - shrink, 0.0), max(rv - shrink, 0.0)
    if a0 is None:
        angles = [-math.pi / 2 + math.pi / sides + 2 * math.pi * i / sides for i in range(sides)]
    else:
        angles = [a0 + (a1 - a0) * i / sides for i in range(sides + 1)]
    pts = []
    for a in angles:
        c, s = math.cos(a), math.sin(a)
        k = 1.0 + (rng.uniform(-jitter, jitter) if rng is not None and jitter > 0.0 else 0.0)
        u = cu + k * ru * math.copysign(abs(c) ** (2.0 / ex), c)
        v = cv + k * rv * math.copysign(abs(s) ** (2.0 / ex), s)
        pts.append(_axis_point(axis, t, u, v))
    return pts


def loft(name, rings, material, sides=8, axis="z", jitter=0.0, tones=True):
    """Faceted tube through `rings` (see _ring_points), capped at both ends; a ring with zero
    radii ends the tube in a point."""
    rng = _rng(name + "/jitter")
    bm = bmesh.new()
    loops = []
    for ring in rings:
        if ring[3] <= 1e-6 and ring[4] <= 1e-6:
            loops.append([bm.verts.new(_axis_point(axis, ring[0], ring[1], ring[2]))])
        else:
            loops.append([bm.verts.new(p) for p in _ring_points(ring, sides, axis, jitter=jitter, rng=rng)])
    for a, b in zip(loops, loops[1:]):
        if len(a) == 1 or len(b) == 1:
            pole, ring = (a[0], b) if len(a) == 1 else (b[0], a)
            for i in range(len(ring)):
                bm.faces.new((pole, ring[i], ring[(i + 1) % len(ring)]))
            continue
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a[i], a[j], b[j], b[i]))
    for end in (loops[0], loops[-1]):
        if len(end) > 2:
            bm.faces.new(end)
    return _finish(name, bm, material, tones)


def shell(name, rings, material, centre, half_spans, thickness, sides=10, jitter=0.0, tones=True):
    """Thick open garment around a vertical axis (open jacket, collar, beard, headphone band):
    on each ring the arc centre +- half_span (rad; -pi/2 = front), outer surface on the ring,
    inner surface `thickness` further in, all edges closed."""
    rng = _rng(name + "/jitter")
    bm = bmesh.new()
    outer, inner = [], []
    for ring, h in zip(rings, half_spans):
        outer.append([bm.verts.new(p) for p in _ring_points(
            ring, sides, "z", centre - h, centre + h, jitter=jitter, rng=rng)])
        inner.append([bm.verts.new(p) for p in _ring_points(
            ring, sides, "z", centre - h, centre + h, shrink=thickness)])
    last = len(rings) - 1
    for r in range(last):
        for k in range(sides):
            bm.faces.new((outer[r][k], outer[r][k + 1], outer[r + 1][k + 1], outer[r + 1][k]))
            bm.faces.new((inner[r][k], inner[r + 1][k], inner[r + 1][k + 1], inner[r][k + 1]))
        for k in (0, sides):
            bm.faces.new((outer[r][k], outer[r + 1][k], inner[r + 1][k], inner[r][k]))
    for r in (0, last):
        for k in range(sides):
            bm.faces.new((outer[r][k], outer[r][k + 1], inner[r][k + 1], inner[r][k]))
    return _finish(name, bm, material, tones)


def hull(name, points, material, tones=True):
    """Convex faceted chunk through `points` (hair tufts, nose, ears, hands, laces)."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(Vector(p))
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    junk = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    return _finish(name, bm, material, tones)


def ball(name, centre, radius, material, sides=8, rings=4):
    """Low-poly sphere (joint fills at knees and elbows)."""
    cx, cy, cz = centre
    spec = []
    for k in range(rings + 1):
        phi = -math.pi / 2 + math.pi * k / rings
        r = radius * math.cos(phi) if 0 < k < rings else 0.0
        spec.append((cz + radius * math.sin(phi), cx, cy, r, r))
    return loft(name, spec, material, sides=sides)


def _ring_at(rings, z):
    """(cx, cy, rx, ry, ex) of a vertical loft at height z (linear between rings)."""
    for a, b in zip(rings, rings[1:]):
        if a[0] <= z <= b[0]:
            f = (z - a[0]) / (b[0] - a[0])
            cx, cy, rx, ry = (a[i] + (b[i] - a[i]) * f for i in (1, 2, 3, 4))
            return cx, cy, rx, ry, (a[5] if len(a) > 5 else 2.0)
    raise ValueError(f"z={z} outside the loft")


def _front_y(rings, x, z):
    """y of the front (-Y) surface of a vertical loft at (x, z), without jitter."""
    cx, cy, rx, ry, ex = _ring_at(rings, z)
    q = min(abs(x - cx) / rx, 1.0) ** ex
    return cy - ry * (1.0 - q) ** (1.0 / ex)


def patch(name, rings, x0, x1, z0, z1, depth, material, lift=0.0, steps=4):
    """Thin slab lying on the front of a vertical loft (pocket, buckle, shirt print)."""
    pts = []
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        for z in (z0, z1):
            y = _front_y(rings, x, z) - lift
            pts += [(x, y + 0.004, z), (x, y - depth, z)]
    return hull(name, pts, material, tones=False)


# Vertical cross-sections (z, cx, cy, rx, ry[, ex]) of the character, in metres.
JACKET = [(0.83, 0, 0.000, 0.188, 0.125, 2.4), (0.95, 0, 0.000, 0.182, 0.122, 2.4),
          (1.10, 0, -0.004, 0.200, 0.132, 2.4), (1.26, 0, -0.008, 0.215, 0.138, 2.4),
          (1.36, 0, 0.000, 0.220, 0.125, 2.4), (1.395, 0, 0.004, 0.190, 0.112, 2.4),
          (1.425, 0, 0.008, 0.140, 0.095, 2.4)]
JACKET_OPEN = (0.17, 0.17, 0.19, 0.22, 0.28, 0.40, 0.55)   # half opening at the front (rad)
SHIRT = [(0.955, 0, 0.000, 0.158, 0.100, 2.4), (1.00, 0, 0.000, 0.158, 0.100, 2.4),
         (1.15, 0, -0.004, 0.175, 0.108, 2.4), (1.26, 0, -0.008, 0.188, 0.112, 2.4),
         (1.36, 0, 0.000, 0.188, 0.100, 2.4), (1.425, 0, 0.008, 0.115, 0.075, 2.4),
         (1.47, 0, 0.010, 0.055, 0.050, 2.2)]
PELVIS = [(0.73, 0, 0.005, 0.095, 0.065, 2.2), (0.785, 0, 0.000, 0.158, 0.098, 2.4),
          (0.88, 0, 0.000, 0.160, 0.100, 2.4), (0.97, 0, 0.000, 0.152, 0.096, 2.4)]
BELT = [(0.925, 0, 0.000, 0.159, 0.104, 2.4), (0.965, 0, 0.000, 0.157, 0.103, 2.4)]
HEAD = [(1.470, 0, -0.050, 0.035, 0.030), (1.490, 0, -0.035, 0.075, 0.075),
        (1.530, 0, -0.010, 0.105, 0.105), (1.590, 0, 0.000, 0.122, 0.122),
        (1.650, 0, 0.005, 0.124, 0.124), (1.710, 0, 0.012, 0.108, 0.112),
        (1.750, 0, 0.015, 0.068, 0.072), (1.765, 0, 0.015, 0.0, 0.0)]
# Hairline height by angular distance from the front (rad): forehead, temples, over the ears, nape.
HAIRLINE = ((0.0, 1.690), (0.7, 1.668), (1.25, 1.642), (1.75, 1.636), (2.2, 1.555), (math.pi, 1.500))


def _hairline(d):
    for (d0, z0), (d1, z1) in zip(HAIRLINE, HAIRLINE[1:]):
        if d <= d1:
            return z0 + (z1 - z0) * (d - d0) / (d1 - d0)
    return HAIRLINE[-1][1]


def _head_point(z, a, out):
    cx, cy, rx, ry, _ex = _ring_at(HEAD, z)
    return Vector((cx + (rx + out) * math.cos(a), cy + (ry + out) * math.sin(a), z))


def _build_hair():
    rng = _rng("hair")
    pts = [(0.0, 0.015, 1.786)]
    levels = [1.50 + 0.025 * i for i in range(11)]
    for k in range(20):
        a = -math.pi / 2 + 2 * math.pi * k / 20
        line = _hairline(abs(math.remainder(a + math.pi / 2, 2 * math.pi)))
        for z in [line] + [z for z in levels if z > line + 0.01]:
            pts.append(tuple(_head_point(z, a, 0.014 + rng.uniform(0.0, 0.008))))
    hull("hair", pts, "castano")
    # Carved locks lying on the hair: (angle from the front, height, length, sweep, width).
    # The fringe is swept to one side, the top backwards and the back downwards.
    fringe, top, side, nape = (0.7, 0.2, 0.55), (0.3, 0.8, 0.45), (0.0, 0.8, -0.3), (0.0, 0.45, -1.0)
    tufts = [(-0.55, 1.700, 0.040, fringe, 0.034), (-0.15, 1.712, 0.046, fringe, 0.036),
             (0.25, 1.708, 0.044, fringe, 0.034), (0.62, 1.692, 0.036, (0.6, 0.4, 0.3), 0.030),
             (-0.35, 1.748, 0.040, top, 0.036), (0.30, 1.750, 0.040, top, 0.036),
             (-1.05, 1.690, 0.034, side, 0.030), (1.05, 1.690, 0.034, side, 0.030),
             (-1.60, 1.668, 0.030, side, 0.028), (1.60, 1.668, 0.030, side, 0.028),
             (math.pi - 0.7, 1.720, 0.036, nape, 0.034), (math.pi + 0.7, 1.720, 0.036, nape, 0.034),
             (math.pi, 1.660, 0.034, nape, 0.034)]
    for i, (d, z, length, sweep, w) in enumerate(tufts):
        a = -math.pi / 2 + d
        base = _head_point(z, a, 0.012)
        n = Vector((math.cos(a), math.sin(a), (z - 1.60) / 0.12)).normalized()
        side = Vector((-math.sin(a), math.cos(a), 0.0))
        up = n.cross(side).normalized()
        tip = base + (n * 0.35 + Vector(sweep).normalized()).normalized() * length \
            + side * rng.uniform(-0.008, 0.008)
        w += rng.uniform(-0.004, 0.004)
        hull(f"hair_lock_{i}", [tuple(p) for p in (base - n * 0.022, base + side * w, base - side * w,
                                                   base + up * w * 0.8, base - up * w * 0.6, tip)], "castano")


def _build_face():
    for sx in (-1, 1):
        hull(f"ear_{sx}", [(sx * 0.116, -0.012, 1.565), (sx * 0.116, 0.022, 1.575), (sx * 0.116, 0.018, 1.632),
                           (sx * 0.116, -0.010, 1.625), (sx * 0.136, -0.004, 1.572), (sx * 0.141, 0.018, 1.585),
                           (sx * 0.139, 0.016, 1.628), (sx * 0.134, -0.002, 1.620)], "piel")
        box(f"eye_{sx}", (0.022, 0.012, 0.017), (sx * 0.042, -0.116, 1.603), "tinta")
        box(f"brow_{sx}", (0.042, 0.012, 0.012), (sx * 0.044, -0.119, 1.638), "pelo", rot=(0, sx * 0.16, 0))
        # Glasses: two open rims, bridge, hinges and temples back to the ears.
        gx, gy, gz, w, h, bar = sx * 0.045, -0.129, 1.604, 0.058, 0.042, 0.007
        box(f"glasses_top_{sx}", (w, 0.006, bar), (gx, gy, gz + h / 2), "tinta")
        box(f"glasses_bottom_{sx}", (w, 0.006, bar), (gx, gy, gz - h / 2), "tinta")
        box(f"glasses_in_{sx}", (bar, 0.006, h), (gx - sx * w / 2, gy, gz), "tinta")
        box(f"glasses_out_{sx}", (bar, 0.006, h), (gx + sx * w / 2, gy, gz), "tinta")
        box(f"glasses_hinge_{sx}", (0.056, 0.006, 0.007), (sx * 0.101, -0.127, gz + 0.012), "tinta")
        box(f"glasses_temple_{sx}", (0.006, 0.124, 0.007), (sx * 0.128, -0.064, gz + 0.012), "tinta")
    box("glasses_bridge", (0.022, 0.006, 0.006), (0.0, -0.129, 1.611), "tinta")
    hull("nose", [(0.0, -0.110, 1.622), (0.017, -0.112, 1.578), (-0.017, -0.112, 1.578), (0.0, -0.146, 1.572),
                  (0.011, -0.134, 1.565), (-0.011, -0.134, 1.565), (0.0, -0.122, 1.561)], "piel")
    # Short beard: chin and jaw (front arc), sideburns in front of the ears, moustache, mouth.
    shell("beard", [(1.452, 0, -0.056, 0.038, 0.034), (1.478, 0, -0.040, 0.074, 0.072),
                    (1.505, 0, -0.024, 0.097, 0.096), (1.530, 0, -0.011, 0.112, 0.111),
                    (1.552, 0, -0.006, 0.119, 0.118)],
          "castano", -math.pi / 2, (1.6, 1.75, 1.85, 1.9, 1.9), 0.022, sides=12, jitter=0.02)
    for sx, centre in ((1, -0.35), (-1, math.pi + 0.35)):
        shell(f"sideburn_{sx}", [(1.530, 0, -0.010, 0.116, 0.116), (1.590, 0, 0.0, 0.132, 0.132),
                                 (1.640, 0, 0.004, 0.134, 0.134)],
              "castano", centre, (0.22, 0.22, 0.2), 0.022, sides=3)
    hull("moustache", [(0.034, -0.118, 1.546), (-0.034, -0.118, 1.546), (0.022, -0.131, 1.552),
                       (-0.022, -0.131, 1.552), (0.0, -0.136, 1.556), (0.0, -0.124, 1.565),
                       (0.03, -0.121, 1.539), (-0.03, -0.121, 1.539)], "castano")
    box("mouth", (0.032, 0.006, 0.006), (0.0, -0.134, 1.532), "tinta")


def _build_torso():
    shell("jacket", JACKET, "salvia", math.pi / 2, [math.pi - g for g in JACKET_OPEN], 0.018,
          sides=16, jitter=0.015)
    shell("jacket_collar", [(1.395, 0, 0.010, 0.112, 0.088, 2.2), (1.440, 0, 0.012, 0.086, 0.073, 2.2),
                            (1.485, 0, 0.014, 0.078, 0.068, 2.2)],
          "salvia_oscura", math.pi / 2, (2.25, 2.3, 2.35), 0.014, sides=12)
    patch("jacket_pocket", JACKET, -0.150, -0.080, 1.17, 1.24, 0.006, "salvia_oscura")
    loft("shirt", SHIRT, "hueso", sides=12)
    patch("shirt_print", SHIRT, -0.026, 0.026, 1.205, 1.255, 0.004, "grafito")
    patch("shirt_print_cursor", SHIRT, -0.014, 0.004, 1.222, 1.230, 0.003, "mostaza", lift=0.004)
    loft("jeans_hips", PELVIS, "vaquero", sides=12)
    loft("belt", BELT, "cuero", sides=12)
    patch("belt_buckle", BELT, -0.022, 0.022, 0.928, 0.962, 0.007, "acero")
    loft("neck", [(1.40, 0, 0.010, 0.050, 0.047), (1.505, 0, 0.012, 0.046, 0.044)], "piel")
    loft("head", HEAD, "piel", sides=12)


def build_character_player():
    """The player character (~1.78 m with hair): a homelab tinkerer in an open sage overshirt,
    T-shirt with a terminal print, jeans and trainers, glasses and a short beard. Faceted low-poly in the game palette. Articulated exactly like the mannequin
    (J_hip / J_knee / J_ankle, J_shoulder / J_elbow, suffix _L / _R) for CharacterAnimator."""
    for sx, side in ((-1, "L"), (1, "R")):
        x = sx * 0.085
        hip = empty(f"J_hip_{side}", (x, 0, 0.84), size=0.05)
        knee = empty(f"J_knee_{side}", (x, 0, 0.44), size=0.05)
        ankle = empty(f"J_ankle_{side}", (x, 0, 0.07), size=0.05)
        parent_keep(loft(f"thigh_{sx}", [(0.43, x, 0.000, 0.051, 0.055), (0.48, x, 0.000, 0.058, 0.062),
                                         (0.62, x, -0.004, 0.068, 0.072),
                                         (0.78, x + sx * 0.004, -0.004, 0.077, 0.080),
                                         (0.90, x + sx * 0.004, 0.000, 0.074, 0.076)],
                         "vaquero", jitter=0.03), hip)
        parent_keep(ball(f"knee_{sx}", (x, 0, 0.44), 0.052, "vaquero"), knee)
        parent_keep(loft(f"shin_{sx}", [(0.09, x, 0.000, 0.044, 0.047), (0.16, x, 0.000, 0.046, 0.049),
                                        (0.27, x, 0.006, 0.049, 0.053), (0.37, x, 0.008, 0.054, 0.058),
                                        (0.47, x, 0.000, 0.052, 0.055)], "vaquero", jitter=0.03), knee)
        parent_keep(loft(f"hem_{sx}", [(0.105, x, 0, 0.052, 0.055), (0.125, x, 0, 0.056, 0.059),
                                       (0.155, x, 0, 0.053, 0.056)], "vaquero_claro"), knee)
        parent_keep(loft(f"shoe_{sx}", [(0.088, x, 0.050, 0.030, 0.030, 2.2), (0.070, x, 0.058, 0.047, 0.048, 2.2),
                                        (0.020, x, 0.064, 0.054, 0.054, 2.2), (-0.040, x, 0.050, 0.056, 0.040, 2.2),
                                        (-0.095, x, 0.040, 0.053, 0.030, 2.2), (-0.135, x, 0.034, 0.042, 0.022, 2.2),
                                        (-0.150, x, 0.030, 0.020, 0.012, 2.2)], "grafito", axis="y", jitter=0.03),
                    ankle)
        parent_keep(loft(f"sole_{sx}", [(0.092, x, 0.011, 0.036, 0.011, 3.0), (0.075, x, 0.011, 0.052, 0.011, 3.5),
                                        (-0.090, x, 0.011, 0.058, 0.011, 3.5), (-0.140, x, 0.012, 0.046, 0.011, 3.0),
                                        (-0.156, x, 0.014, 0.024, 0.009, 2.5)], "hueso", axis="y", tones=False),
                    ankle)
        parent_keep(hull(f"laces_{sx}", [(x + 0.020, 0.000, 0.118), (x - 0.020, 0.000, 0.118),
                                         (x + 0.016, -0.070, 0.086), (x - 0.016, -0.070, 0.086),
                                         (x + 0.016, 0.000, 0.104), (x - 0.016, 0.000, 0.104),
                                         (x + 0.012, -0.070, 0.074), (x - 0.012, -0.070, 0.074)],
                         "hueso", tones=False), ankle)
        parent_keep(ankle, knee)
        parent_keep(knee, hip)

        ax = sx * 0.265
        shoulder = empty(f"J_shoulder_{side}", (ax, 0, 1.35), size=0.05)
        elbow = empty(f"J_elbow_{side}", (ax, 0, 1.08), size=0.05)
        parent_keep(loft(f"sleeve_{sx}", [(1.06, ax, 0.0, 0.047, 0.049), (1.12, ax, 0.0, 0.052, 0.054),
                                          (1.25, ax, 0.0, 0.057, 0.059), (1.33, ax, 0.0, 0.059, 0.061),
                                          (1.385, ax - sx * 0.012, 0.0, 0.050, 0.053),
                                          (1.412, ax - sx * 0.028, 0.0, 0.0, 0.0)], "salvia", jitter=0.03),
                    shoulder)
        parent_keep(ball(f"elbow_{sx}", (ax, 0, 1.08), 0.049, "salvia"), elbow)
        parent_keep(loft(f"forearm_{sx}", [(0.855, ax, 0.0, 0.048, 0.050), (0.90, ax, 0.0, 0.050, 0.052),
                                           (1.00, ax, -0.004, 0.052, 0.054), (1.10, ax, 0.0, 0.049, 0.051)],
                         "salvia", jitter=0.03), elbow)
        parent_keep(loft(f"cuff_{sx}", [(0.835, ax, 0, 0.050, 0.052), (0.865, ax, 0, 0.055, 0.057),
                                        (0.885, ax, 0, 0.053, 0.055)], "salvia_oscura"), elbow)
        parent_keep(loft(f"wrist_{sx}", [(0.80, ax, 0, 0.028, 0.030), (0.85, ax, 0, 0.030, 0.032)], "piel"),
                    elbow)
        hx = sx * 0.268
        hand = [(hx + dx, dy, 0.828) for dx in (-0.016, 0.016) for dy in (-0.028, 0.028)]
        hand += [(hx + dx, dy, 0.790) for dx in (-0.021, 0.021) for dy in (-0.044, 0.044)]
        hand += [(hx + dx, dy, 0.760) for dx in (-0.019, 0.019) for dy in (-0.042, 0.042)]
        hand += [(hx + dx, dy, 0.733) for dx in (-0.012, 0.012) for dy in (-0.034, 0.034)]
        hand += [(hx, -0.018, 0.722), (hx, 0.018, 0.722), (hx - sx * 0.016, -0.052, 0.800),
                 (hx - sx * 0.022, -0.060, 0.772), (hx - sx * 0.010, -0.058, 0.765)]
        parent_keep(hull(f"hand_{sx}", hand, "piel"), elbow)
        parent_keep(elbow, shoulder)
    _build_torso()
    _build_face()
    _build_hair()


MODELS = {
    "switch_16p_1u": ("network", build_switch_16p_1u),
    "server_1u_entry": ("compute", build_server_1u_entry),
    "rack_12u_open": ("racks", build_rack_12u_open),
    "router_home": ("network", build_router_home),
    "power_strip_4": ("power", build_power_strip_4),
    "pc_tower_old": ("compute", build_pc_tower_old),
    "monitor_old": ("compute", build_monitor_old),
    "keyboard_mouse": ("compute", build_keyboard_mouse),
    "desk_basic": ("furniture", build_desk),
    "chair_office": ("furniture", build_chair),
    "bed_single": ("furniture", build_bed),
    "cabinet_small": ("furniture", build_cabinet_small),
    "rug_basic": ("furniture", build_rug),
    "package_box": ("props", build_package_box),
    "room_bedroom": ("rooms", build_room_bedroom),
    "mannequin_scale": ("characters", build_mannequin),
    "character_player": ("characters", build_character_player),
}


# ------------------------------------------------------------------- main ---
def _reset_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def _bake_and_strip():
    """Apply all modifiers (bevel, booleans) and delete the cutter objects."""
    deps = bpy.context.evaluated_depsgraph_get()
    for ob in [o for o in bpy.data.objects if o.type == "MESH" and not o.get("is_cutter")]:
        if not ob.modifiers:
            continue
        evaluated = ob.evaluated_get(deps)
        baked = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
        ob.modifiers.clear()
        old = ob.data
        ob.data = baked
        if old.users == 0:
            bpy.data.meshes.remove(old)
    for ob in [o for o in bpy.data.objects if o.get("is_cutter")]:
        bpy.data.objects.remove(ob, do_unlink=True)


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--only", default="")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    selected = [s for s in args.only.split(",") if s] or list(MODELS)
    failures = 0
    for model_id in selected:
        category, builder = MODELS[model_id]
        _reset_scene()
        builder()
        blend_dir = os.path.join(root, "art_source", category)
        glb_dir = os.path.join(root, "assets", "models", category)
        os.makedirs(blend_dir, exist_ok=True)
        os.makedirs(glb_dir, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, model_id + ".blend"), copy=True)
        _bake_and_strip()
        glb_path = os.path.join(glb_dir, model_id + ".glb")
        try:
            bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB", use_selection=False,
                                      export_apply=True, export_yup=True, export_cameras=False,
                                      export_lights=False)
        except TypeError as exc:   # option names changed in this Blender version
            print("EXPORT_OPTION_ERROR", exc)
            bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB")
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
        empties = sorted(o.name for o in bpy.data.objects if o.type == "EMPTY")
        ok = os.path.isfile(glb_path)
        failures += 0 if ok else 1
        print(f"MODEL {model_id}: {'OK' if ok else 'FAIL'} | meshes={len(meshes)} tris={tris} "
              f"empties={len(empties)} -> {os.path.relpath(glb_path, root)}")
    print(f"DONE failures={failures}")
    return failures


if __name__ == "__main__":
    sys.exit(main())
