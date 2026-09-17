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

def revolve(profile, seg=64, closed=False, side_v=(0.0, 0.80), metal_uv=(0.06, 0.26, 0.84, 0.98)):
    """Putar profil (r,y) mengelilingi sumbu Y.
    closed=True  -> profil loop tertutup (torus/pegas), watertight tanpa cap.
    closed=False -> profil terbuka; ujung r=0 jadi pole (cap otomatis).
    UV: sisi = (angle/2pi, t) dipetakan ke side_v; cap = planar ke kotak metal.
    """
    pos, uv, faces = [], [], []
    rings = []
    n = len(profile)

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
    """Hasilkan BaseColor, Roughness, Normal (semua PIL Image RGB)."""
    rng = np.random.default_rng(seed)
    S = size
    # BARIS GAMBAR dari koordinat v:  py = (1 - v) * S
    # (v=0 di dasar badan -> baris bawah gambar; v=1 di puncak -> baris atas)
    side_y0 = int((1.0 - SIDE_V1) * S)     # v=0.80 -> baris 204 (puncak badan)
    side_y1 = int((1.0 - SIDE_V0) * S)     # v=0.00 -> baris 1024 (dasar badan)
    met_y0 = int((1.0 - METAL_V1) * S)     # v=1.00 -> baris 0
    met_y1 = int((1.0 - METAL_V0) * S)     # v=0.82 -> baris 184

    body = spec['body_color']
    label = spec['label_color']
    metal = spec['metal_color']

    # ---- BaseColor ----
    base = Image.new('RGB', (S, S), (60, 62, 66))
    dr = ImageDraw.Draw(base)
    # badan (sisi)
    dr.rectangle([0, side_y0, S, side_y1], fill=body)
    # band label
    for (a, b) in spec.get('label_bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0))
        y1 = side_y0 + int(b * (side_y1 - side_y0))
        dr.rectangle([0, y0, S, y1], fill=label)
    # band logam di sisi (kalau ada, mis. ujung AA)
    for (a, b) in spec.get('metal_bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0))
        y1 = side_y0 + int(b * (side_y1 - side_y0))
        dr.rectangle([0, y0, S, y1], fill=metal)
    # area logam untuk cap
    dr.rectangle([0, met_y0, S, met_y1], fill=metal)

    # noise brushed halus di area logam
    arr = np.array(base).astype(np.float32)
    lum_noise = rng.normal(0, 2.6, (S, S, 1))
    metal_rows = np.zeros((S, S, 1), np.float32)
    metal_rows[met_y0:met_y1, :, 0] = 1.0
    for (a, b) in spec.get('metal_bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0)); y1 = side_y0 + int(b * (side_y1 - side_y0))
        metal_rows[y0:y1, :, 0] = 1.0
    arr = np.clip(arr + lum_noise * (0.35 + 0.65 * metal_rows), 0, 255)
    base = Image.fromarray(arr.astype(np.uint8))
    dr = ImageDraw.Draw(base)

    # garis pemisah band
    for (a, b) in spec.get('label_bands', []) + spec.get('metal_bands', []):
        for e in (a, b):
            y = side_y0 + int(e * (side_y1 - side_y0))
            dr.line([0, y, S, y], fill=tuple(max(0, c - 45) for c in base.getpixel((5, y))), width=3)

    # ---- teks label ----
    # Ukuran huruf proporsional terhadap ukuran nyata baterai (mm),
    # dengan batas maksimum supaya tidak melengkung/pecah di silinder tipis.
    body_h_mm = spec.get('body_h_mm', 50.0)
    body_w_mm = spec.get('body_w_mm', 26.0)
    side_px = side_y1 - side_y0
    repeat = spec.get('text_repeat', 3)   # teks muncul N kali mengelilingi badan
    # batas: teks tidak boleh lebih dari ~42% lebar keliling yang tersedia
    max_fs_by_width = int(S / repeat * 0.42 / 0.62)   # 0.62 ~ lebar rata2 huruf
    # u-center untuk teks: kalau spec kasih 'text_u', pakai itu (tengah sisi depan
    # pada balok); kalau tidak, bagi rata sepanjang keliling (silinder).
    text_u = spec.get('text_u')
    # lebar maksimum teks dalam px = lebar sisi depan (fraksi u) x S
    max_w_px = int(spec.get('max_u_width', 0.9) * S)
    for (text, rel_y, mm_cap, col) in spec.get('texts', []):
        fsize = max(8, int(mm_cap / body_h_mm * side_px))
        fsize = min(fsize, max_fs_by_width)
        # kecilkan font sampai teks muat di lebar sisi
        while fsize > 8:
            f = _font(fsize)
            bb = dr.textbbox((0, 0), text, font=f)
            if bb[2] - bb[0] <= max_w_px:
                break
            fsize = int(fsize * 0.92)
        f = _font(fsize)
        bb = dr.textbbox((0, 0), text, font=f)
        w = bb[2] - bb[0]
        y = side_y0 + int(rel_y * side_px)
        out = tuple(max(0, int(c * 0.28)) for c in col)
        if text_u is not None:
            centers = [text_u] if repeat <= 1 else [text_u, text_u + 0.5]
        else:
            centers = [(r + 0.5) / repeat for r in range(repeat)]
        for uc in centers:
            cx = int((uc % 1.0) * S)
            x = cx - w // 2
            for dx, dy in ((-2,0),(2,0),(0,-2),(0,2),(-1,-1),(1,-1),(-1,1),(1,1)):
                dr.text((x + dx, y + dy), text, font=f, fill=out)
            dr.text((x, y), text, font=f, fill=col)

    # detail: pita aksen
    for (rel_y, hgt, col) in spec.get('stripes', []):
        y = side_y0 + int(rel_y * (side_y1 - side_y0))
        dr.rectangle([0, y, S, y + hgt], fill=col)

    # ---- polaritas +/- di area logam (muncul di cap atas/bawah) ----
    pol = spec.get('polarity')
    if pol:
        px_, py_ = int(0.30 * S), int((1.0 - 0.91) * S)
        col_p = pol
        L_, T_ = int(0.055 * S), int(0.011 * S)
        # plus
        dr.rectangle([px_ - L_, py_ - T_, px_ + L_, py_ + T_], fill=col_p)
        dr.rectangle([px_ - T_, py_ - L_, px_ + T_, py_ + L_], fill=col_p)
        # minus
        mx_ = int(0.70 * S)
        dr.rectangle([mx_ - L_, py_ - T_, mx_ + L_, py_ + T_], fill=col_p)

    # ---- MOTIF HIAS: pita diagonal (bukan barcode!) ----
    # CATATAN PENTING: pola garis-garis rapat menyerupai barcode/QR bisa memicu
    # deteksi otomatis Roblox "Directing Users Off-Platform". Diganti motif
    # geometris yang jelas bukan kode dan tidak bisa dipindai.
    if spec.get('decor_stripes'):
        dy0 = side_y0 + int(0.72 * (side_y1 - side_y0))
        dh = max(10, int(0.06 * (side_y1 - side_y0)))
        dcol = tuple(max(0, int(c * 0.55)) for c in spec['label_color'])
        # pita diagonal lebar, jarak jauh -> jelas ornamen
        step = int(0.075 * S)
        for x in range(-dh, S + dh, step):
            dr.polygon([(x, dy0 + dh), (x + dh, dy0), (x + dh + int(step * 0.45), dy0),
                        (x + int(step * 0.45), dy0 + dh)], fill=dcol)

    # ---- ikon peringatan kecil ----
    if spec.get('warn'):
        wy = side_y0 + int(0.78 * (side_y1 - side_y0))
        wc = int(0.05 * S)
        for i in range(2):
            wx = int((0.18 + i * 0.10) * S)
            dr.polygon([(wx, wy + wc), (wx + wc, wy + wc), (wx + wc // 2, wy)],
                       outline=spec['warn'], width=3)
            dr.line([wx + wc // 2, wy + int(wc * 0.30),
                     wx + wc // 2, wy + int(wc * 0.70)], fill=spec['warn'], width=3)

    # goresan halus
    scr = Image.new('L', (S, S), 0)
    sd = ImageDraw.Draw(scr)
    for _ in range(int(S * 0.18)):
        x1 = int(rng.integers(0, S)); y1 = int(rng.integers(0, S))
        L = int(rng.integers(4, 26)); ang = rng.uniform(0, 2 * math.pi)
        sd.line([x1, y1, x1 + L * math.cos(ang), y1 + L * math.sin(ang)],
                fill=int(rng.integers(70, 150)), width=1)
    scr = scr.filter(ImageFilter.GaussianBlur(0.5))
    sm = np.array(scr).astype(np.float32) / 255
    arr = np.array(base).astype(np.float32)
    for k in range(3):
        arr[:, :, k] = arr[:, :, k] * (1 - sm * 0.14) + 210 * (sm * 0.14)
    base = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.35))

    # ---- Roughness (R) + Metallic (G) dipaket jadi satu (metallicRoughnessTexture) ----
    rough = np.full((S, S), spec.get('rough_body', 0.62), np.float32)
    metal_mask = np.zeros((S, S), np.float32)
    metal_mask[met_y0:met_y1, :] = 1.0
    for (a, b) in spec.get('metal_bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0)); y1 = side_y0 + int(b * (side_y1 - side_y0))
        metal_mask[y0:y1, :] = 1.0
    label_mask = np.zeros((S, S), np.float32)
    for (a, b) in spec.get('label_bands', []):
        y0 = side_y0 + int(a * (side_y1 - side_y0)); y1 = side_y0 + int(b * (side_y1 - side_y0))
        label_mask[y0:y1, :] = 1.0
    rough = np.where(metal_mask > 0.5, spec.get('rough_metal', 0.26), rough)
    rough = np.where(label_mask > 0.5, spec.get('rough_label', 0.66), rough)
    rough = np.clip(rough + rng.normal(0, 0.02, (S, S)), 0.05, 1.0)

    met = np.where(metal_mask > 0.5, 0.92, 0.05).astype(np.float32)
    mr = np.stack([np.zeros_like(rough), met, rough], axis=-1)   # R=0(occlusion), G=metallic, B=roughness
    mr_img = Image.fromarray((np.clip(mr, 0, 1) * 255).astype(np.uint8), 'RGB')

    # ---- Normal dari luminance BaseColor ----
    g = np.array(base.convert('L')).astype(np.float32) / 255.0
    g = np.array(Image.fromarray((g * 255).astype(np.uint8))
                 .filter(ImageFilter.GaussianBlur(1.1))).astype(np.float32) / 255.0
    gx = np.gradient(g, axis=1); gy = np.gradient(g, axis=0)
    st = 1.7
    nx, ny, nz = -gx * st, gy * st, np.ones_like(g)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], -1)
    nrm_img = Image.fromarray((nrm * 255).astype(np.uint8), 'RGB')

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


SPECS = {
    'aa': dict(
        file='baterai_AA.glb', label='AA 1.5V',
        body_color=(58, 60, 68), label_color=(214, 74, 58), metal_color=(198, 200, 205),
        label_bands=[(0.10, 0.70)], metal_bands=[(0.0, 0.10), (0.70, 0.80)],
        rough_body=0.60, rough_label=0.68, rough_metal=0.24,
        body_h_mm=50.5, body_w_mm=14.5, text_repeat=2, text_u=0.75, max_u_width=0.20,
        texts=[('SILENCIO', 0.13, 2.0, (255, 252, 248)),
               ('AA', 0.24, 6.2, (255, 255, 252)),
               ('1.5V', 0.42, 3.6, (255, 252, 246)),
               ('ALKALINE', 0.55, 2.0, (252, 240, 234))],
        stripes=[(0.085, 10, (250, 248, 244)), (0.715, 8, (250, 248, 244))],
        build=build_aa, size_mm=(14.5, 50.5, 14.5), metallic=0.85,
        polarity=(58, 60, 66), decor_stripes=True, warn=(150, 42, 36),
    ),
    '9v': dict(
        file='baterai_9V.glb', label='9V',
        body_color=(52, 54, 62), label_color=(240, 188, 52), metal_color=(202, 204, 209),
        label_bands=[(0.06, 0.74)], metal_bands=[],
        rough_body=0.62, rough_label=0.64, rough_metal=0.22,
        body_h_mm=45.0, body_w_mm=26.5, text_repeat=2, text_u=0.849, max_u_width=0.28,
        texts=[('SILENCIO', 0.08, 2.2, (26, 20, 10)),
               ('9V', 0.20, 7.4, (22, 16, 6)),
               ('ALKALINE', 0.48, 2.4, (32, 24, 12)),
               ('LONG LIFE', 0.60, 2.0, (40, 30, 16))],
        stripes=[(0.055, 10, (250, 248, 244)), (0.735, 10, (250, 248, 244))],
        build=build_9v, size_mm=(26.5, 48.5, 17.5), metallic=0.80,
        polarity=(34, 28, 12), decor_stripes=True, warn=(140, 44, 30),
    ),
    'lantern': dict(
        file='baterai_6V_lantern.glb', label='6V Lantern',
        body_color=(50, 52, 60), label_color=(62, 118, 186), metal_color=(200, 202, 207),
        label_bands=[(0.08, 0.70)], metal_bands=[],
        rough_body=0.62, rough_label=0.60, rough_metal=0.24,
        body_h_mm=103.2, body_w_mm=67.0, text_repeat=2, text_u=0.875, max_u_width=0.23,
        texts=[('SILENCIO', 0.10, 3.4, (252, 254, 255)),
               ('6V', 0.22, 10.0, (255, 255, 252)),
               ('LANTERN', 0.44, 4.6, (244, 250, 255)),
               ('4R25 ZINC', 0.58, 2.8, (228, 240, 250))],
        stripes=[(0.075, 12, (246, 248, 252)), (0.695, 12, (246, 248, 252))],
        build=build_lantern, size_mm=(67, 115, 67), metallic=0.75,
        polarity=(58, 60, 66), decor_stripes=True, warn=(180, 62, 40),
    ),
    'sla': dict(
        file='baterai_SLA.glb', label='SLA / aki kecil',
        body_color=(48, 54, 58), label_color=(46, 126, 88), metal_color=(196, 198, 203),
        label_bands=[(0.14, 0.66)], metal_bands=[],
        rough_body=0.66, rough_label=0.62, rough_metal=0.30,
        body_h_mm=88.0, body_w_mm=98.0, text_repeat=2, text_u=0.829, max_u_width=0.32,
        texts=[('SILENCIO', 0.10, 3.2, (248, 252, 250)),
               ('12V', 0.22, 9.4, (252, 255, 253)),
               ('7Ah', 0.42, 5.0, (244, 250, 247)),
               ('LEAD ACID', 0.56, 2.8, (232, 242, 238))],
        stripes=[(0.135, 10, (250, 248, 244)), (0.655, 10, (250, 248, 244))],
        build=build_sla, size_mm=(98, 100, 45), metallic=0.70,
        polarity=(58, 60, 66), decor_stripes=True, warn=(196, 74, 42),
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
    # simpan preview texture
    base.save(os.path.join(outdir, f"_{key}_BaseColor.png"))
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
