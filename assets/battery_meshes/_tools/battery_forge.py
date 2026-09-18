"""
battery_forge.py — generator mesh + texture baterai 3D (CC0, buatan sendiri)

Dipakai untuk mini games Control Room 3 (Silencio).
Menghasilkan .glb dengan TEXTURE TER-EMBED (satu file, tidak ada texture terpisah)
sehingga Roblox Studio langsung membaca texture-nya saat import.

Semua output CC0 / public domain — 100% buatan sendiri.
"""

import struct, json, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ============================================================
# 1. MESH CORE
# ============================================================

def revolve(profile, seg=64, closed=False, side_v=(0.0, 0.80), metal_uv=(0.06, 0.26, 0.84, 0.98),
            metal_side=False):
    # metal_side=True -> sisi ikut dipetakan ke area logam (v 0.82-1.00),
    # bukan area badan. Dipakai untuk terminal/tiang yang harus terlihat metalik.
    """Putar profil (r,y) mengelilingi sumbu Y.
    closed=True  -> profil loop tertutup (torus/pegas), watertight tanpa cap.
    closed=False -> profil terbuka; ujung r=0 jadi pole (cap otomatis).
    UV: sisi = (angle/2pi, t) dipetakan ke side_v; cap = planar ke kotak metal.
    """
    pos, uv, faces = [], [], []
    rings = []
    n = len(profile)

    if metal_side:
        side_v = (0.84, 0.98)          # area logam, bukan badan
    for i, (r, y) in enumerate(profile):
        # closed=True: profil melingkar (torus/pegas) -> t = i/n, ring terakhir nyambung ke pertama
        t = (i / n) if closed else (i / (n - 1) if n > 1 else 0.0)
        if abs(r) < 1e-9 and not closed:
            pos.append((0.0, y, 0.0))
            uv.append((0.5, side_v[0] + t * (side_v[1] - side_v[0])))
            rings.append([len(pos) - 1])
        else:
            ring = []
            for s in range(seg + 1):          # +1: duplikat di u=1.0 (fix seam)
                a = 2 * math.pi * (s % seg) / seg
                pos.append((r * math.cos(a), y, r * math.sin(a)))
                # u dibalik (1 - s/seg): supaya tidak MIRROR saat dilihat dari luar
                uv.append((1.0 - s / seg, side_v[0] + t * (side_v[1] - side_v[0])))
                ring.append(len(pos) - 1)
            rings.append(ring)

    # sambung ring berurutan (closed: ring terakhir balik ke ring pertama)
    if closed:
        pairs = [(rings[i], rings[(i + 1) % len(rings)]) for i in range(len(rings))]
    else:
        pairs = [(rings[i], rings[i + 1]) for i in range(len(rings) - 1)]

    for a, b in pairs:
        if len(a) == 1:
            for s in range(seg):
                faces.append((a[0], b[s], b[s + 1]))
        elif len(b) == 1:
            for s in range(seg):
                faces.append((a[s], b[0], a[s + 1]))
        else:
            for s in range(seg):
                faces.append((a[s], b[s], b[s + 1]))
                faces.append((a[s], b[s + 1], a[s + 1]))

    # tutup ujung terbuka: DUPLIKAT vertex ring supaya UV sisi tidak ketimpa
    if not closed:
        u0, u1, v0, v1 = metal_uv
        for end, is_top in ((0, False), (len(profile) - 1, True)):
            r, y = profile[end]
            if abs(r) < 1e-9:
                continue
            src_ring = rings[end]
            # duplikat vertex ring dengan UV planar (kotak logam)
            cap_ring = []
            for vi in src_ring:
                x, _, z = pos[vi]
                cap_ring.append(len(pos))
                pos.append((x, y, z))
                uv.append((u0 + (u1 - u0) * (x / r * 0.5 + 0.5),
                           v0 + (v1 - v0) * (z / r * 0.5 + 0.5)))
            # pusat cap
            ci = len(pos)
            pos.append((0.0, y, 0.0))
            uv.append(((u0 + u1) / 2, (v0 + v1) / 2))
            for s in range(seg):
                if is_top:
                    faces.append((ci, cap_ring[s], cap_ring[s + 1]))
                else:
                    faces.append((ci, cap_ring[s + 1], cap_ring[s]))

    return pos, uv, faces


def rounded_rect_poly(w, d, r, seg_corner=10):
    """Poligon rounded-rect di bidang XZ (urutan CCW dilihat dari +Y)."""
    hw, hd = w / 2.0, d / 2.0
    r = max(0.0, min(r, hw, hd))
    pts = []
    corners = [(hw - r, hd - r, 0.0), (-hw + r, hd - r, 90.0),
               (-hw + r, -hd + r, 180.0), (hw - r, -hd + r, 270.0)]
    for cx, cz, a0 in corners:
        for i in range(seg_corner + 1):
            a = math.radians(a0 + 90.0 * i / seg_corner)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    # buang duplikat berurutan
    out = []
    for p in pts:
        if not out or (abs(p[0] - out[-1][0]) > 1e-7 or abs(p[1] - out[-1][1]) > 1e-7):
            out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) < 1e-7 and abs(out[0][1] - out[-1][1]) < 1e-7:
        out.pop()
    return out


def build_box(w, d, h, radius=3.0, seg_corner=10, side_v=(0.0, 0.80),
              metal_uv=(0.06, 0.26, 0.84, 0.98)):
    """Balok rounded-rect di-extrude sepanjang Y. UV sisi = (perimeter, tinggi)."""
    poly = rounded_rect_poly(w, d, radius, seg_corner)
    n = len(poly)
    # panjang kumulatif untuk u
    cum = [0.0]
    for i in range(1, n + 1):
        a, b = poly[i - 1], poly[i % n]
        cum.append(cum[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = cum[-1]

    pos, uv, faces = [], [], []
    bot, top = [], []
    y0, y1 = -h / 2.0, h / 2.0
    # +1 vertex duplikat (menutup seam). u DIBALIK (1 - cum/total) supaya
    # teks tidak MIRROR saat sisi dilihat dari luar.
    for i in range(n + 1):
        x, z = poly[i % n]
        u = (0.0 if i == n else 1.0 - cum[i] / total)
        pos.append((x, y0, z)); uv.append((u, side_v[0])); bot.append(len(pos) - 1)
    for i in range(n + 1):
        x, z = poly[i % n]
        u = (0.0 if i == n else 1.0 - cum[i] / total)
        pos.append((x, y1, z)); uv.append((u, side_v[1])); top.append(len(pos) - 1)

    # sisi
    for i in range(n):
        faces.append((bot[i], bot[i + 1], top[i + 1]))
        faces.append((bot[i], top[i + 1], top[i]))

    # cap atas & bawah: DUPLIKAT vertex ring supaya UV sisi tidak ketimpa
    u0, u1, v0, v1 = metal_uv
    hw, hd = w / 2.0, d / 2.0
    def cap_uv(x, z):
        return (u0 + (u1 - u0) * (x / hw * 0.5 + 0.5),
                v0 + (v1 - v0) * (z / hd * 0.5 + 0.5))
    for y, ring, is_top in ((y1, top, True), (y0, bot, False)):
        cap_ring = []
        for vi in ring:
            x, _, z = pos[vi]
            cap_ring.append(len(pos))
            pos.append((x, y, z))
            uv.append(cap_uv(x, z))
        ci = len(pos); pos.append((0.0, y, 0.0)); uv.append(((u0 + u1) / 2, (v0 + v1) / 2))
        for i in range(n):
            if is_top:
                faces.append((ci, cap_ring[i], cap_ring[i + 1]))
            else:
                faces.append((ci, cap_ring[i + 1], cap_ring[i]))

    return pos, uv, faces


def merge(*parts):
    pos, uv, faces = [], [], []
    for p, u, f in parts:
        off = len(pos)
        pos += p; uv += u
        faces += [(a + off, b + off, c + off) for a, b, c in f]
    return pos, uv, faces


def finalize(pos, uv, faces):
    """Hitung normal per-vertex, perbaiki winding via uji volume, validasi."""
    P = np.array(pos, np.float64)
    F = np.array(faces, np.int64)
    v0, v1, v2 = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    vol = float(np.einsum('ij,ij->i', v0, np.cross(v1, v2)).sum() / 6.0)
    if vol < 0:
        F = F[:, [0, 2, 1]]
        vol = -vol
    N = np.zeros_like(P)
    fn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    for k in range(3):
        np.add.at(N, F[:, k], fn)
    ln = np.linalg.norm(N, axis=1, keepdims=True)
    ln[ln < 1e-12] = 1.0
    N = N / ln
    return P, N.astype(np.float32), np.array(uv, np.float32), F.astype(np.uint32), vol


# ============================================================
# 2. GLB WRITER (texture TER-EMBED)
# ============================================================

def write_glb(path, P, N, UV, F, images, mat_name, metallic, roughness):
    """Tulis GLB dengan gambar PNG ter-embed di chunk BIN (satu file, tanpa texture terpisah)."""
    blob = bytearray()
    views = []

    def add_view(data, target=None):
        pad = (4 - len(blob) % 4) % 4
        if pad:
            blob.extend(b'\x00' * pad)
        bv = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
        if target:
            bv['target'] = target
        views.append(bv)
        blob.extend(data)
        return len(views) - 1

    vpos = np.asarray(P, np.float32); vnrm = np.asarray(N, np.float32)
    vuv = np.asarray(UV, np.float32); vidx = np.asarray(F, np.uint32).flatten()

    i_pos = add_view(vpos.tobytes(), 34962)
    i_nrm = add_view(vnrm.tobytes(), 34962)
    i_uv = add_view(vuv.tobytes(), 34962)
    i_idx = add_view(vidx.tobytes(), 34963)
    img_views = []
    for png, mime in images:
        img_views.append((add_view(png), mime))

    mn = vpos.min(0).tolist(); mx = vpos.max(0).tolist()
    gltf = {
        'asset': {'version': '2.0', 'generator': 'hermes-battery-forge'},
        'scene': 0, 'scenes': [{'nodes': [0]}],
        'nodes': [{'mesh': 0, 'name': mat_name}],
        'meshes': [{'name': mat_name, 'primitives': [{
            'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2},
            'indices': 3, 'material': 0}]}],
        'materials': [{'name': mat_name, 'pbrMetallicRoughness': {
            'baseColorTexture': {'index': 0},
            'metallicRoughnessTexture': {'index': 2},
            'metallicFactor': metallic, 'roughnessFactor': roughness},
            'normalTexture': {'index': 1, 'scale': 0.85},
            'doubleSided': False}],
        'textures': [{'source': 0}, {'source': 1}, {'source': 2}],
        'images': [{'bufferView': img_views[0][0], 'mimeType': img_views[0][1]},
                   {'bufferView': img_views[1][0], 'mimeType': img_views[1][1]},
                   {'bufferView': img_views[2][0], 'mimeType': img_views[2][1]}],
        'accessors': [
            {'bufferView': i_pos, 'componentType': 5126, 'count': len(vpos), 'type': 'VEC3',
             'min': mn, 'max': mx},
            {'bufferView': i_nrm, 'componentType': 5126, 'count': len(vnrm), 'type': 'VEC3'},
            {'bufferView': i_uv, 'componentType': 5126, 'count': len(vuv), 'type': 'VEC2'},
            {'bufferView': i_idx, 'componentType': 5125, 'count': len(vidx), 'type': 'SCALAR'}],
        'bufferViews': views,
        'buffers': [{'byteLength': len(blob)}],
    }
    jb = json.dumps(gltf, separators=(',', ':')).encode()
    jb += b' ' * ((4 - len(jb) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(blob)
    with open(path, 'wb') as f:
        f.write(b'glTF' + struct.pack('<II', 2, total))
        f.write(struct.pack('<I4s', len(jb), b'JSON')); f.write(jb)
        f.write(struct.pack('<I4s', len(blob), b'BIN\x00')); f.write(blob)
    return total


# ============================================================
# 3. TEXTURE
# ============================================================

def _font(size, bold=True):
    for name in (f'C:/Windows/Fonts/arial{"bd" if bold else ""}.ttf',
                 f'C:/Windows/Fonts/arial.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            continue
    return ImageFont.load_default()


SIDE_V0, SIDE_V1 = 0.0, 0.80          # region sisi di texture (v)
METAL_V0, METAL_V1 = 0.82, 1.00       # region logam (cap) di texture


def make_textures(spec, size=1024, seed=7):
    """Texture POLOS: hanya blok warna rata. TANPA teks, corak, noise, atau tanda.
    Sesuai permintaan Aer: warna polos saja (1-3 warna), tidak ada corak aneh.

    Layout (v -> baris gambar):
      v 0.00-0.80 = sisi badan   -> baris 204..1024
      v 0.82-1.00 = logam (cap)  -> baris 0..184
    """
    S = size
    side_y0 = int((1.0 - SIDE_V1) * S)      # 204 (puncak badan)
    side_y1 = int((1.0 - SIDE_V0) * S)      # 1024 (dasar badan)
    met_y0 = int((1.0 - METAL_V1) * S)      # 0
    met_y1 = int((1.0 - METAL_V0) * S)      # 184

    base = Image.new('RGB', (S, S), spec['metal_color'])
    dr = ImageDraw.Draw(base)

    # --- sisi badan: warna polos ---
    dr.rectangle([0, side_y0, S, side_y1], fill=spec['body_color'])

    # --- pita warna kedua (opsional) ---
    # band = (fraksi_awal, fraksi_akhir, warna) relatif terhadap tinggi badan
    for (a, b, col) in spec.get('bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0))
        y1 = side_y0 + int(b * (side_y1 - side_y0))
        dr.rectangle([0, y0, S, y1], fill=col)

    # --- area logam untuk cap ---
    dr.rectangle([0, met_y0, S, met_y1], fill=spec['metal_color'])

    base = base  # sengaja tanpa filter/noise

    # --- Roughness + Metallic dipaket (G=metallic, B=roughness) ---
    rough = np.full((S, S), spec.get('rough_body', 0.55), np.float32)
    metal_mask = np.zeros((S, S), np.float32)
    metal_mask[met_y0:met_y1, :] = 1.0
    for (a, b, col) in spec.get('metal_bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0))
        y1 = side_y0 + int(b * (side_y1 - side_y0))
        metal_mask[y0:y1, :] = 1.0
    rough = np.where(metal_mask > 0.5, spec.get('rough_metal', 0.28), rough)
    met = np.where(metal_mask > 0.5, 0.90, 0.04).astype(np.float32)
    mr = np.stack([np.zeros_like(rough), met, rough], axis=-1)
    mr_img = Image.fromarray((np.clip(mr, 0, 1) * 255).astype(np.uint8), 'RGB')

    # --- Normal map: DIBUAT DATAR (tanpa detail permukaan) ---
    # Karena tidak ada corak, normal map cukup flat (128,128,255).
    flat = np.zeros((S, S, 3), np.uint8)
    flat[:, :, 0] = 128; flat[:, :, 1] = 128; flat[:, :, 2] = 255
    # Pertahankan sedikit bevel di batas warna supaya tidak terlihat datar total
    nrm_img = Image.fromarray(flat, 'RGB')

    return base, mr_img, nrm_img


def png_bytes(img):
    import io
    b = io.BytesIO()
    img.save(b, format='PNG', optimize=True)
    return b.getvalue(), 'image/png'


# ============================================================
# 4. PREVIEW RENDER (painter's algorithm)
# ============================================================

def render_preview(P, N, UV, F, tex, W=420, H=420, view='iso', bg=(20, 21, 24)):
    """Render sederhana: sortir face berdasarkan kedalaman, gambar polygon."""
    P = np.asarray(P, np.float64); N = np.asarray(N, np.float64)
    UV = np.asarray(UV, np.float64); F = np.asarray(F, np.int64)
    V = P.copy()
    if view == 'iso':
        a, b = math.radians(28), math.radians(58)
        R1 = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
        R2 = np.array([[1, 0, 0], [0, math.cos(b), -math.sin(b)], [0, math.sin(b), math.cos(b)]])
        V = V @ R1.T @ R2.T
        Nn = N @ R1.T @ R2.T
    elif view == 'front':
        Nn = N.copy()
    else:  # top
        V = V[:, [0, 2, 1]].copy()
        Nn = N[:, [0, 2, 1]].copy()
    pts = V[:, :2]; dep = V[:, 2]
    mn, mx = pts.min(0), pts.max(0)
    span = max((mx - mn).max(), 1e-9)
    sc = (min(W, H) * 0.80) / span
    c = (mn + mx) / 2
    xy = (pts - c) * sc + np.array([W / 2, H / 2]); xy[:, 1] = H - xy[:, 1]

    tarr = np.asarray(tex.convert('RGB'))
    ts = tarr.shape[0]
    light = np.array([0.42, 0.74, 0.52]); light /= np.linalg.norm(light)

    img = Image.new('RGB', (W, H), bg)
    dr = ImageDraw.Draw(img)
    order = np.argsort(dep[F].mean(1))
    for i in order:
        t = F[i]
        p = xy[t]
        if p[:, 0].max() < 0 or p[:, 0].min() > W or p[:, 1].max() < 0 or p[:, 1].min() > H:
            continue
        uvc = UV[t].mean(0)
        px = int(np.clip(uvc[0] % 1.0 * (ts - 1), 0, ts - 1))
        py = int(np.clip((1.0 - (uvc[1] % 1.0)) * (ts - 1), 0, ts - 1))
        col = tarr[py, px].astype(np.float32)
        lam = 0.42 + 0.58 * abs(float(np.dot(Nn[t].mean(0), light)))
        col = np.clip(col * lam, 0, 255).astype(int)
        dr.polygon([tuple(p[0]), tuple(p[1]), tuple(p[2])], fill=tuple(col))
    return img


# ============================================================
# 5. VALIDASI
# ============================================================

def validate(P, N, UV, F):
    from collections import Counter
    P = np.asarray(P, np.float64); F = np.asarray(F, np.int64)
    rep = {}
    v0, v1, v2 = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    rep['volume_mm3'] = float(np.einsum('ij,ij->i', v0, np.cross(v1, v2)).sum() / 6.0)
    rep['tris'] = len(F); rep['verts'] = len(P)
    rep['degenerate'] = int(sum(1 for t in F if len(set(t.tolist())) < 3))
    e = Counter()
    for t in F:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            e[tuple(sorted((int(a), int(b))))] += 1
    rep['open_edges'] = int(sum(1 for v in e.values() if v != 2))
    rep['watertight'] = rep['open_edges'] == 0
    rep['winding_ok'] = rep['volume_mm3'] > 0
    ln = np.linalg.norm(np.asarray(N, np.float64), axis=1)
    rep['normal_unit'] = bool(abs(ln.mean() - 1.0) < 1e-3)
    U = np.asarray(UV, np.float64)
    rep['uv_in_range'] = bool(U.min() >= -1e-6 and U.max() <= 1 + 1e-6)
    rep['dims_mm'] = [round(float(x), 2) for x in (P.max(0) - P.min(0))]
    return rep


# ============================================================
# 6. SPESIFIKASI BATERAI
# ============================================================

def build_aa():
    """AA 1.5V: silinder 14.5 x 50.5 mm (termasuk nub positif), dasar cekung."""
    r = 7.25
    # total tinggi 50.5 (termasuk nub 1.0 mm), terpusat di y=0
    prof = [
        (0.0, -25.25),      # pusat dasar (cekung)
        (5.40, -25.25),     # dasar rata
        (5.40, -24.55),     # dinding cekungan
        (r, -24.55),        # ke radius penuh
        (r, 24.25),         # dinding badan
        (r - 0.35, 24.25),  # bibir atas
        (2.75, 24.25),      # bahu atas
        (2.75, 25.25),      # dinding nub
        (0.0, 25.25),       # puncak nub
    ]
    return revolve(prof, seg=64)


def build_9v():
    """9V: balok 26.5 x 17.5 x 48.5 mm (termasuk terminal) + 2 terminal di atas."""
    BODY_H = 45.0                      # 48.5 total - 3.5 terminal
    body = build_box(26.5, 17.5, BODY_H, radius=2.2, seg_corner=6)
    # terminal bulat (positif)
    t1 = revolve([(0.0, 0.0), (3.4, 0.0), (3.4, 2.7), (3.15, 3.5), (0.0, 3.5)], seg=24)
    # terminal segi enam (negatif)
    t2 = revolve([(0.0, 0.0), (5.0, 0.0), (5.0, 2.8), (4.6, 3.5), (0.0, 3.5)], seg=6)

    def shift(part, dx, dy, dz):
        p, u, ff = part
        return [(x + dx, y + dy, z + dz) for (x, y, z) in p], u, ff

    top = BODY_H / 2
    return merge(body, shift(t1, -7.0, top, 0.0), shift(t2, 6.5, top, 0.0))


def build_lantern():
    """6V Lantern 4R25: 67 x 67 x 115 mm (termasuk 2 pegas spiral)."""
    SPRING_H = 11.8                    # 3 torus, jarak 4.0, tube 1.9
    BODY_H = 115.0 - SPRING_H          # = 103.2
    body = build_box(67, 67, BODY_H, radius=6.0, seg_corner=6)

    top = BODY_H / 2
    springs = []
    for sx in (-20.0, 20.0):
        for k in range(3):
            cy = top + 1.9 + k * 4.0
            R0, rr = 9.0, 1.9
            prof = [(R0 + rr * math.cos(2 * math.pi * i / 16),
                     rr * math.sin(2 * math.pi * i / 16)) for i in range(16)]
            sp = revolve(prof, seg=24, closed=True)
            springs.append(([(x + sx, y + cy, z) for (x, y, z) in sp[0]], sp[1], sp[2]))
    return merge(body, *springs)


def build_sla():
    """SLA / aki kecil: 98 x 45 x 100 mm (termasuk 2 tab pipih)."""
    TAB_H = 12.0
    BODY_H = 100.0 - TAB_H             # = 88.0
    body = build_box(98, 45, BODY_H, radius=5.0, seg_corner=6)
    top = BODY_H / 2
    tabs = []
    for sx in (-26.0, 26.0):
        tab = build_box(16, 3.2, TAB_H, radius=1.2, seg_corner=4)
        # tab diletakkan DI ATAS badan (bukan separuh tenggelam)
        dy = top + TAB_H / 2
        tabs.append(([(x + sx, y + dy, z) for (x, y, z) in tab[0]], tab[1], tab[2]))
    return merge(body, *tabs)


def build_powercell():
    """Power cell: balok 52 x 52 x 88 mm + 2 tiang terminal perak di atas."""
    BODY_H = 76.0                      # 88 total - 12 terminal
    body = build_box(52, 52, BODY_H, radius=4.0, seg_corner=6)
    top = BODY_H / 2
    posts = []
    for sx in (-14.0, 14.0):
        # tiang terminal perak (silinder kecil)
        post = revolve([(0.0, 0.0), (6.0, 0.0), (6.0, 9.0), (5.4, 11.0), (0.0, 11.0)], seg=24, metal_side=True)
        posts.append(([(x + sx, y + top, z) for (x, y, z) in post[0]], post[1], post[2]))
    return merge(body, *posts)


SPECS = {
    'aa': dict(
        file='baterai_AA.glb', label='AA',
        # 2 warna polos: badan + pita. Tanpa teks/corak.
        body_color=(38, 92, 176),           # biru
        bands=[(0.0, 0.10, (196, 198, 203)),   # pita logam di dasar
               (0.90, 1.0, (196, 198, 203))],  # pita logam di puncak
        metal_color=(198, 200, 205),
        rough_body=0.48, rough_metal=0.26,
        metallic=0.85,
        build=build_aa, size_mm=(14.5, 50.5, 14.5),
    ),
    '9v': dict(
        file='baterai_9V.glb', label='9V',
        body_color=(96, 100, 110),          # abu medium
        bands=[(0.38, 0.58, (236, 190, 66))],  # pita kuning di tengah (kelihatan dari atas)
        metal_color=(202, 204, 209),
        rough_body=0.52, rough_metal=0.24,
        metallic=0.80,
        build=build_9v, size_mm=(26.5, 48.5, 17.5),
    ),
    'lantern': dict(
        file='baterai_6V_lantern.glb', label='6V Lantern',
        body_color=(52, 138, 92),           # hijau
        bands=[(0.0, 0.12, (206, 208, 213)),
               (0.88, 1.0, (206, 208, 213))],
        metal_color=(200, 202, 207),
        rough_body=0.52, rough_metal=0.26,
        metallic=0.75,
        build=build_lantern, size_mm=(67, 115, 67),
    ),
    'powercell': dict(
        file='baterai_powercell.glb', label='Power Cell',
        # Power cell: badan gelap polos, kutub atas PERAK metalik.
        body_color=(58, 62, 72),            # abu gelap (diterangkan sedikit)
        # cincin perak DIPERLEBAR & DIPINDAH ke v 0.68-0.80 (lebih kelihatan, jauh dari plat)
        bands=[(0.04, 0.18, (202, 204, 209))],  # cincin perak dekat puncak
        metal_color=(210, 212, 217),        # perak lebih terang
        metal_bands=[(0.04, 0.18, (202, 204, 209))],  # cincin perak = logam
        rough_body=0.46, rough_metal=0.14,  # roughness rendah = mengilap
        metallic=0.92,
        build=build_powercell, size_mm=(52, 88, 52),
    ),
    'sla': dict(
        file='baterai_SLA.glb', label='SLA',
        body_color=(168, 66, 56),           # merah bata
        bands=[(0.38, 0.56, (206, 208, 213))],  # pita terang di tengah
        metal_color=(196, 198, 203),
        rough_body=0.56, rough_metal=0.30,
        metallic=0.70,
        build=build_sla, size_mm=(98, 100, 45),
    ),
}


# ============================================================
# 7. MAIN
# ============================================================

def build_one(key, outdir):
    spec = SPECS[key]
    pos, uv, f = spec['build']()
    P, N, UV, F, vol = finalize(pos, uv, f)
    base, mr, nrm = make_textures(spec, seed=hash(key) % 1000)
    imgs = [png_bytes(base), png_bytes(mr), png_bytes(nrm)]
    path = os.path.join(outdir, spec['file'])
    total = write_glb(path, P, N, UV, F, imgs, spec['label'],
                      spec['metallic'], 1.0)
    rep = validate(P, N, UV, F)
    rep['file'] = spec['file']
    rep['bytes'] = total
    rep['label'] = spec['label']
    return rep, (P, N, UV, F, base)


def main(outdir=None):
    outdir = outdir or os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.dirname(outdir) if os.path.basename(outdir) == '_tools' else outdir
    reports = []
    for k in SPECS:
        rep, data = build_one(k, outdir)
        reports.append((k, rep, data))
        print(f"[{k}] {rep['file']}: {rep['tris']} tri, {rep['verts']} vert, "
              f"{rep['bytes']:,} B, dims {rep['dims_mm']}")
        print(f"      watertight={rep['watertight']} winding={rep['winding_ok']} "
              f"vol={rep['volume_mm3']:.1f} uv_ok={rep['uv_in_range']} "
              f"degenerate={rep['degenerate']} normal_unit={rep['normal_unit']}")
    return reports


if __name__ == '__main__':
    main()
