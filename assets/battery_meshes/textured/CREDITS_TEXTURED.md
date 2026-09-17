# Mesh Baterai BERTEXTURE — CC0

Dua model baterai bertekstur asli, keduanya **CC0 (public domain)** — bebas dipakai
komersial, **tanpa wajib kredit**.

Sumber: [OpenGameArt.org](https://opengameart.org)
Tanggal unduh: 15 Sep 2026

---

## 1. Battery RC — CC0

**Lokasi:** `textured/battery_rc_cc0/battery/`
**Halaman asal:** <https://opengameart.org/content/battery-for-rc-cars-etc>
**Lisensi:** CC0 (dikonfirmasi dari badge `cc0.png` di halaman)

| File | Isi |
|---|---|
| `battery.obj` | Mesh — 251 vertex, 244 face (sangat ringan) |
| `battery.mtl` | Material — referensi ke `battery.png` |
| `battery.png` | **Diffuse texture 512×512** (186 KB) |
| `ao.png` | **Ambient Occlusion map 512×512** (105 KB) |
| `battery.blend` | File Blender sumber (bisa diabaikan) |
| `battery.psd` | File Photoshop sumber (bisa diabaikan) |

**Kelebihan:** poly count rendah (244 face — sangat ringan untuk Roblox), punya AO map
(bisa dipakai sebagai `SurfaceAppearance` biar lebih berdimensi), texture 512×512 pas.

**Material MTL:**
```
newmtl green_untitled.001
Kd 0.071108 0.230631 0.064207   <- warna dasar hijau gelap
map_Kd battery.png              <- diffuse texture
```

---

## 2. Stylized Battery — CC0

**Lokasi:** `textured/battery_stylized_cc0/`
**Halaman asal:** <https://opengameart.org/content/3d-stylized-battery-with-texture-and-template-texture>
**Lisensi:** CC0 (dikonfirmasi dari badge `cc0.png` di halaman)

| File | Isi |
|---|---|
| `bat.fbx` | Mesh (binary FBX) |
| `Battery 4k.png` | **Texture 2048×2048** (492 KB) |
| `Battery 4k2.png` | **Texture 2731×2731** (29,9 MB — SANGAT BESAR) |

**⚠️ Perhatian:**
- `Battery 4k2.png` ukurannya **29,9 MB** — **JANGAN upload apa adanya ke Roblox**.
  Batas texture Roblox 1024×1024 (bisa sampai 2048 untuk kasus khusus). Harus di-resize dulu.
- `Battery 4k.png` (2048×2048, 492 KB) masih bisa dipakai, tapi tetap dianjurkan resize ke 1024.
- FBX mereferensikan path lokal pembuat (`C:\Users\cars6\Desktop\...`) — texture harus
  di-assign manual saat impor.
- `bat.fbx` ukurannya cuma 77 KB tapi mesh-nya kemungkinan lebih padat dari model RC.

---

## Rekomendasi Pemakaian

| Kebutuhan | Pakai yang mana |
|---|---|
| **Cepat, ringan, aman** | `battery_rc_cc0` — 244 face, texture 512×512 siap pakai |
| **Detail tinggi (close-up)** | `battery_stylized_cc0` + resize texture ke 1024 dulu |
| **Banyak copy di map** | `battery_rc_cc0` (jauh lebih ringan) |
| **Butuh AO map** | `battery_rc_cc0` (punya `ao.png`) |

**Saran gua:** pakai **`battery_rc_cc0`** sebagai basis utama. Ringan, texture pas,
punya AO, dan 244 face artinya bisa dipasang puluhan copy tanpa masalah performa.
Model stylized simpan buat 1-2 baterai hero (yang ditonjolkan dekat kamera).

---

## Cara Impor ke Roblox Studio

**Format OBJ (battery_rc_cc0):**
1. View → **Asset Manager** → **Bulk Import** → **3D Models**
2. Pilih `battery.obj` + `battery.png` (dan `ao.png` kalau mau AO)
3. Roblox otomatis bikin MeshPart + SurfaceAppearance

**Format FBX (battery_stylized_cc0):**
1. **Resize dulu** `Battery 4k2.png` ke maksimal 1024×1024 (pakai Paint/PowerToys/ffmpeg)
2. Baru import `bat.fbx` + texture hasil resize
3. Assign texture manual kalau Roblox gak otomatis kebaca

**Catatan:** Model bertexture masuk sebagai MeshPart + `SurfaceAppearance`
(diffuse → ColorMap, AO → bisa dipakai di slot lain). Beda dengan 13 model tanpa
texture sebelumnya yang cuma punya warna material solid.

---

## Ringkasan Semua Aset Baterai

| Folder | Jumlah | Texture | Lisensi |
|---|---|---|---|
| `battery_meshes/*.glb` (root) | 13 model | ❌ warna solid saja | 4 CC0 + 9 CC-BY 3.0 |
| `battery_meshes/textured/battery_rc_cc0` | 1 model | ✅ 512×512 + AO | **CC0** |
| `battery_meshes/textured/battery_stylized_cc0` | 1 model | ✅ 2048 & 2731 | **CC0** |

Kredit untuk 9 model CC-BY ada di `CREDITS.md`.
