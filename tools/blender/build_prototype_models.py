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
import sys

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


def build_room_bedroom():
    """3.5 x 3.0 m bedroom shell. Floor top at z=0. Back wall at +Y, left wall at -X.
    Front (-Y) and right (+X) walls are the 'cutaway' low versions (camera side)."""
    W, D, H, T = 3.5, 3.0, 2.6, 0.10
    planks = 14
    pw = W / planks
    for i in range(planks):
        box(f"floor_plank_{i}", (pw, D, 0.04), (-W / 2 + pw * (i + 0.5), 0, -0.02),
            "madera" if i % 2 == 0 else "madera_oscura", chamfer=0.06)
    back = box("WALL_back", (W + 2 * T, T, H), (0, D / 2 + T / 2, H / 2), "hueso")
    cut(back, [((1.10, 0.3, 1.10), (0.55, D / 2 + T / 2, 1.45))], "niebla")
    box("window_frame_top", (1.16, 0.14, 0.05), (0.55, D / 2 + T / 2, 2.025), "niebla", chamfer=0.2)
    box("window_frame_bottom", (1.24, 0.20, 0.05), (0.55, D / 2 + T / 2 - 0.03, 0.875), "niebla", chamfer=0.2)
    for sx in (-1, 1):
        box(f"window_frame_side_{sx}", (0.05, 0.14, 1.10), (0.55 + sx * 0.575, D / 2 + T / 2, 1.45), "niebla", chamfer=0.2)
    box("window_mullion", (0.035, 0.10, 1.10), (0.55, D / 2 + T / 2, 1.45), "niebla")
    box("window_glass", (1.10, 0.01, 1.10), (0.55, D / 2 + T / 2, 1.45), "cristal")
    box("window_sky", (1.6, 0.02, 1.6), (0.55, D / 2 + T + 0.25, 1.45), "cielo")
    door_y, door_w = -1.02, 0.80          # near the camera-side corner, clear of the bed
    left = box("WALL_left", (T, D, H), (-W / 2 - T / 2, 0, H / 2), "hueso")
    cut(left, [((0.3, door_w, 2.08), (-W / 2 - T / 2, door_y, 1.04))], "madera")
    for sy in (-1, 1):
        box(f"door_frame_{sy}", (0.14, 0.05, 2.12), (-W / 2 - T / 2, door_y + sy * (door_w / 2 + 0.025), 1.06),
            "madera", chamfer=0.2)
    box("door_frame_top", (0.14, door_w + 0.10, 0.05), (-W / 2 - T / 2, door_y, 2.105), "madera", chamfer=0.2)
    box("door", (0.04, door_w - 0.02, 2.06), (-W / 2 - T / 2 + 0.03, door_y, 1.03), "madera_oscura", chamfer=0.15)
    cylinder("door_handle", 0.012, 0.08, (-W / 2 + 0.03, door_y + 0.30, 1.0), "acero", rot=(0, math.pi / 2, 0))
    # skirting boards
    box("skirting_back", (W, 0.015, 0.08), (0, D / 2 - 0.0075, 0.04), "terracota")
    box("skirting_left", (0.015, D, 0.08), (-W / 2 + 0.0075, 0, 0.04), "terracota")
    # cutaway walls (camera side)
    box("WALL_front_cut", (W + 2 * T, T, 0.30), (0, -D / 2 - T / 2, 0.15), "hueso", chamfer=0.1)
    box("WALL_right_cut", (T, D, 0.30), (W / 2 + T / 2, 0, 0.15), "hueso", chamfer=0.1)
    box("wall_cap_front", (W + 2 * T, T + 0.01, 0.02), (0, -D / 2 - T / 2, 0.31), "grafito")
    box("wall_cap_right", (T + 0.01, D, 0.02), (W / 2 + T / 2, 0, 0.31), "grafito")
    empty("DELIVERY_POINT", (-W / 2 + 0.45, door_y, 0))


def build_mannequin():
    """Scale mannequin (~1.75 m), NOT the final character: proportions reference only."""
    for sx in (-1, 1):
        box(f"leg_{sx}", (0.13, 0.15, 0.80), (sx * 0.085, 0, 0.44), "tinta", chamfer=0.3)
        box(f"shoe_{sx}", (0.13, 0.24, 0.07), (sx * 0.085, -0.03, 0.035), "grafito", chamfer=0.4)
        box(f"arm_{sx}", (0.095, 0.11, 0.54), (sx * 0.265, 0, 1.08), "salvia", chamfer=0.4)
        sphere(f"hand_{sx}", 0.055, (sx * 0.27, 0, 0.79), "piel", segments=10, rings=7)
    box("torso", (0.44, 0.25, 0.60), (0, 0, 1.12), "salvia", chamfer=0.35)
    cylinder("neck", 0.055, 0.08, (0, 0, 1.45), "piel", segments=10)
    sphere("head", 0.145, (0, 0, 1.60), "piel", segments=14, rings=10, scale=(1.0, 0.95, 1.05))
    sphere("hair", 0.152, (0, 0.02, 1.64), "pelo", segments=14, rings=10, scale=(1.03, 1.0, 0.85))
    for sx in (-1, 1):
        sphere(f"eye_{sx}", 0.018, (sx * 0.05, -0.135, 1.60), "tinta", segments=8, rings=6)


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
