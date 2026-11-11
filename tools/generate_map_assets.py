from pathlib import Path
import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / 'assets' / 'maps'
MAPS.mkdir(parents=True, exist_ok=True)

# Palette deliberately uses solid vertex colours only: prototype-first, no image textures.
COLORS = {
    'foundation': [55, 65, 72, 255],
    'rim': [91, 105, 111, 255],
    'grass_a': [104, 151, 93, 255],
    'grass_b': [95, 140, 85, 255],
    'road_edge': [125, 91, 61, 255],
    'road': [194, 164, 119, 255],
    'gate': [166, 92, 72, 255],
    'core_base': [82, 104, 118, 255],
    'core_ring': [76, 178, 199, 255],
    'core': [91, 203, 224, 255],
}
scene = trimesh.Scene()

def color_mesh(mesh, color):
    # Use a real glTF PBR material instead of vertex colors alone.
    # Some runtime importers do not enable vertex_color_use_as_albedo by default,
    # which made the whole prototype board appear grey in Godot.
    material = trimesh.visual.material.PBRMaterial(
        name=f"Prototype_{color[0]:02x}{color[1]:02x}{color[2]:02x}",
        baseColorFactor=[int(channel) for channel in color],
        metallicFactor=0.0,
        roughnessFactor=1.0,
        doubleSided=True,
    )
    mesh.visual = trimesh.visual.TextureVisuals(material=material)
    return mesh

def add_box(name, center, extents, color):
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation(center)
    color_mesh(mesh, color)
    scene.add_geometry(mesh, node_name=name, geom_name=name)

def add_cylinder(name, center, radius, height, color, sections=12):
    mesh = trimesh.creation.cylinder(radius=radius, height=height, sections=sections)
    mesh.apply_translation(center)
    color_mesh(mesh, color)
    scene.add_geometry(mesh, node_name=name, geom_name=name)

def add_ribbon(name, points, width, y, color):
    pts = [np.array([p[0], p[2]], dtype=float) for p in points]
    half = width / 2.0
    offsets = []
    for i, p in enumerate(pts):
        if i == 0:
            d = pts[1] - pts[0]
            d /= max(np.linalg.norm(d), 1e-9)
            side = np.array([-d[1], d[0]])
            off = side * half
        elif i == len(pts) - 1:
            d = pts[-1] - pts[-2]
            d /= max(np.linalg.norm(d), 1e-9)
            side = np.array([-d[1], d[0]])
            off = side * half
        else:
            d0 = pts[i] - pts[i - 1]
            d1 = pts[i + 1] - pts[i]
            d0 /= max(np.linalg.norm(d0), 1e-9)
            d1 /= max(np.linalg.norm(d1), 1e-9)
            s0 = np.array([-d0[1], d0[0]])
            s1 = np.array([-d1[1], d1[0]])
            m = s0 + s1
            ml = np.linalg.norm(m)
            if ml < 1e-6:
                m, ml = s1, np.linalg.norm(s1)
            m /= max(ml, 1e-9)
            denom = max(abs(float(np.dot(m, s1))), 0.35)
            off = m * min(half / denom, half * 2.2)
        offsets.append(off)
    verts, faces = [], []
    for p, off in zip(pts, offsets):
        verts.extend([[p[0]-off[0], y, p[1]-off[1]], [p[0]+off[0], y, p[1]+off[1]]])
    for i in range(len(pts)-1):
        k = 2*i
        faces.extend([[k, k+1, k+2], [k+1, k+3, k+2]])
    mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
    color_mesh(mesh, color)
    scene.add_geometry(mesh, node_name=name, geom_name=name)

# 9 x 9 grid, matching Board._default_path() in Godot.
grid = 9
z = grid - 1
direction = 1
spacing = max(1, int((grid - 1) / 2.0))
path_cells = []
while True:
    xs = range(grid) if direction > 0 else range(grid-1, -1, -1)
    for x in xs:
        path_cells.append((x-4, 0.084, z-4))
    if z == 0:
        break
    next_z = max(z-spacing, 0)
    connector_x = grid-1 if direction > 0 else 0
    for zz in range(z-1, next_z-1, -1):
        path_cells.append((connector_x-4, 0.084, zz-4))
    z = next_z
    direction *= -1

# Foundation and a restrained rim.
add_box('Prototype_Foundation', (0, -0.22, 0), (9.65, 0.32, 9.65), COLORS['foundation'])
add_box('Prototype_Rim_North', (0, -0.015, -4.78), (9.6, 0.12, 0.16), COLORS['rim'])
add_box('Prototype_Rim_South', (0, -0.015, 4.78), (9.6, 0.12, 0.16), COLORS['rim'])
add_box('Prototype_Rim_West', (-4.78, -0.015, 0), (0.16, 0.12, 9.6), COLORS['rim'])
add_box('Prototype_Rim_East', (4.78, -0.015, 0), (0.16, 0.12, 9.6), COLORS['rim'])

# Flat tiles with a small gap so the board reads as a grid.
mesh_a, mesh_b = [], []
for row in range(grid):
    for col in range(grid):
        tile = trimesh.creation.box(extents=[0.94, 0.12, 0.94])
        tile.apply_translation([col-4, -0.06, row-4])
        color_mesh(tile, COLORS['grass_a'] if (row+col)%2 == 0 else COLORS['grass_b'])
        (mesh_a if (row+col)%2 == 0 else mesh_b).append(tile)
scene.add_geometry(trimesh.util.concatenate(mesh_a), node_name='Grass_Tiles_A', geom_name='Grass_Tiles_A')
scene.add_geometry(trimesh.util.concatenate(mesh_b), node_name='Grass_Tiles_B', geom_name='Grass_Tiles_B')

# Road is continuous, raised slightly above the grass tiles. Remove consecutive
# duplicate waypoints for mesh generation; Board keeps its logical waypoint list.
road_points = []
for point in path_cells:
    if not road_points or np.linalg.norm(np.array(point) - np.array(road_points[-1])) > 1e-6:
        road_points.append(point)
add_ribbon('Road_Edge', road_points, width=0.98, y=0.052, color=COLORS['road_edge'])
add_ribbon('Road_Surface', road_points, width=0.82, y=0.084, color=COLORS['road'])

# Simple spawn marker at first waypoint.
start = path_cells[0]
add_box('Spawn_Post_Left', (start[0]-0.47, 0.33, start[2]), (0.12, 0.66, 0.14), COLORS['gate'])
add_box('Spawn_Post_Right', (start[0]+0.47, 0.33, start[2]), (0.12, 0.66, 0.14), COLORS['gate'])
add_box('Spawn_Top', (start[0], 0.68, start[2]), (1.05, 0.12, 0.14), COLORS['gate'])

# Simple core at final waypoint.
end = path_cells[-1]
add_cylinder('Core_Base', (end[0], 0.17, end[2]), 0.66, 0.28, COLORS['core_base'], 8)
add_cylinder('Core_Ring', (end[0], 0.34, end[2]), 0.49, 0.06, COLORS['core_ring'], 16)
crystal = trimesh.creation.icosphere(subdivisions=1, radius=0.34)
crystal.apply_scale([0.76, 1.35, 0.76])
crystal.apply_translation([end[0], 0.83, end[2]])
color_mesh(crystal, COLORS['core'])
scene.add_geometry(crystal, node_name='Core_Crystal', geom_name='Core_Crystal')

scene.metadata.update({
    'title': 'Hand Defense - Mapa Prototipo Simples',
    'description': 'Mapa 9x9 sem texturas de imagem; cores chapadas; estrada elevada alinhada a Board._default_path.',
    'grid_size': [9, 9], 'tile_size': 1.0,
    'road_y': 0.084,
    'path_cells': [[int(round(p[0]+4)), int(round(p[2]+4))] for p in path_cells],
    'start_xz': [start[0], start[2]], 'core_xz': [end[0], end[2]],
})

out = MAPS / 'arena_prototipo.glb'
out.write_bytes(trimesh.exchange.gltf.export_glb(scene))
print(f'GLB: {out} ({out.stat().st_size} bytes), geometries={len(scene.geometry)}, waypoints={len(path_cells)}')

# Clear top-down preview; it is a guide, not a baked texture.
fig, ax = plt.subplots(figsize=(8, 8), dpi=150)
ax.set_facecolor('#26343b')
ax.add_patch(Rectangle((-4.75, -4.75), 9.5, 9.5, facecolor='#37434a', edgecolor='#64737b', linewidth=5, zorder=0))
for row in range(grid):
    for col in range(grid):
        c = '#68975d' if (row+col)%2 == 0 else '#5f8c55'
        ax.add_patch(Rectangle((col-4-0.47, row-4-0.47), 0.94, 0.94, facecolor=c, edgecolor='#4f704b', linewidth=0.35, zorder=1))
xs = [p[0] for p in path_cells]
zs = [p[2] for p in path_cells]
ax.plot(xs, zs, color='#7d5b3d', linewidth=38, solid_capstyle='round', solid_joinstyle='round', zorder=3)
ax.plot(xs, zs, color='#c2a477', linewidth=31, solid_capstyle='round', solid_joinstyle='round', zorder=4)
# Entry and core markers.
ax.add_patch(Circle((start[0], start[2]), 0.38, color='#a65c48', zorder=5))
ax.add_patch(Circle((end[0], end[2]), 0.52, color='#4cb2c7', zorder=5))
ax.add_patch(Circle((end[0], end[2]), 0.30, color='#5bcbe0', zorder=6))
ax.text(start[0]+0.75, start[2]+0.15, 'ENTRADA', color='white', fontsize=9, weight='bold', zorder=7)
ax.text(end[0]-0.2, end[2]-0.82, 'NÚCLEO', color='white', fontsize=9, weight='bold', ha='center', zorder=7)
ax.set_xlim(-5.3, 5.3); ax.set_ylim(5.3, -5.3); ax.set_aspect('equal'); ax.axis('off')
fig.subplots_adjust(0,0,1,1)
preview = MAPS / 'preview_arena_prototipo.png'
fig.savefig(preview, transparent=False, facecolor='#26343b')
plt.close(fig)
print('Preview:', preview)
