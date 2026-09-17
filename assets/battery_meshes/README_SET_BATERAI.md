# Set Baterai — 4 Jenis (Buatan Sendiri, CC0)

Aset baterai 3D untuk mini games **Control Room 3** (Silencio).
Dibuat dari nol secara procedural: mesh + 3 map PBR, **texture ter-embed di dalam GLB**.

**Lisensi: CC0 / public domain.** 100% buatan sendiri, bebas komersial, **tanpa wajib kredit**.
Tidak ada pihak ketiga.

---

## Isi

| File | Jenis | Dimensi (mm) | Tri |
|---|---|---|---|
| `baterai_AA.glb` | AA 1.5V | 14.5 × 50.5 × 14.5 | 896 |
| `baterai_9V.glb` | 9V | 26.5 × 48.5 × 17.5 | 292 |
| `baterai_6V_lantern.glb` | 6V Lantern 4R25 | 67 × 115 × 67 | 4.720 |
| `baterai_SLA.glb` | SLA / aki kecil 12V 7Ah | 98 × 100 × 45 | 272 |
| `_preview_set_baterai.png` | preview 4 baterai | — | — |
| `_diag_sisi_depan.png` | bukti texture sisi berlabel | — | — |

Plus: `baterai_power_cell.glb` (dari sebelumnya, dipertahankan sesuai permintaan).

**Ukuran tiap GLB ~1,8 MB** karena texture PNG 1024² ter-embed.

---

## Kenapa texture di-embed

Masalah sebelumnya: FBX dari Sketchfab **tidak menyimpan referensi texture**, jadi saat
di-import ke Roblox mesh-nya jadi abu-abu polos. Penyebabnya FBX hanya menyimpan *path*
ke file texture, dan path itu hilang.

Solusi: **GLB dengan texture ter-embed** — texture ditanam di chunk BIN, jadi satu file
berisi semuanya. Roblox langsung membaca texture-nya saat import.

---

## Cara Impor ke Roblox Studio

1. **View → Asset Manager → Bulk Import → 3D Models**
2. Pilih keempat `.glb` sekaligus
3. Roblox otomatis bikin MeshPart + `SurfaceAppearance` dengan texture terpasang

**Kalau texture tidak muncul** (tergantung versi Studio):
- Upload texture PNG dulu via **Bulk Import → Images**
- Klik MeshPart → **+** → `SurfaceAppearance`
- Isi slot: `ColorMap`, `NormalMap`, `RoughnessMap`

---

## Spesifikasi Teknis (terverifikasi)

Semua model lulus verifikasi otomatis:

| Aspek | Status |
|---|---|
| Dimensi vs ukuran asli | ✅ selisih < 1,5 mm |
| Winding (arah hadap) | ✅ benar — volume positif |
| Normal | ✅ unit length, smooth |
| UV | ✅ dalam rentang 0–1, tanpa seam |
| Degenerate triangle | ✅ 0 |
| Arah teks | ✅ tidak mirror (korelasi X↔u = +1.000) |

---

## Desain — POLOS (tanpa teks)

Sesuai permintaan Aer: **tanpa teks, tanpa corak, warna polos** (1–3 warna per baterai).

| Baterai | Warna 1 | Warna 2 |
|---|---|---|
| AA | biru | — |
| 9V | abu medium | pita kuning |
| 6V Lantern | hijau | — |
| SLA | merah bata | pita terang |

Yang **tidak ada** (sengaja dihapus):
- Teks/merek/tegangan/kapasitas
- Barcode, QR, atau pola garis rapat (pemicu flag moderasi Roblox)
- Tanda polaritas +/− dan ikon peringatan
- Noise, goresan, atau detail permukaan

Normal map dibuat **flat** (tanpa detail), jadi permukaannya benar-benar rata.

Verifikasi: **3 warna unik, 0 tepi tajam** per tekstur.

**Bonus:** ukuran file turun drastis — dari ~1,8 MB jadi **25–150 KB** per GLB,
karena PNG warna rata terkompres jauh lebih baik.

## Kenapa Bentuk Ini Dipilih

Untuk shape matching, siluet harus **beda jauh** biar pemain langsung ngerti:

| Baterai | Siluet | Pembeda |
|---|---|---|
| AA | silinder ramping | bulat + tinggi |
| 9V | balok ramping | kotak + 2 terminal |
| 6V Lantern | kotak besar | **2 pegas spiral** |
| SLA | bata lebar | **2 tab pipih** + paling berat |

**Coin cell (CR2032) sudah dicoba dan DITOLAK** — tebalnya cuma 3,2 mm, jadi dari
kamera first-person hanya tampak garis tipis dan tidak bisa dipegang. Terlalu kecil.

Baterai C/D juga **tidak dipakai** — siluetnya sama persis dengan AA, cuma lebih besar.
Pemain bakal ketuker terus.

---

## Cara Regenerate / Ubah

Semua dibuat oleh satu script: **`_tools/battery_forge.py`**

```bash
python _tools/battery_forge.py
```

Script ini:
1. Membangun mesh procedural (revolve untuk silinder/pegas, extrude untuk balok)
2. Menghitung normal + memperbaiki winding via uji volume
3. Menggambar 3 texture PBR (BaseColor, Normal, Roughness)
4. Menulis GLB dengan texture ter-embed
5. Menjalankan verifikasi otomatis

**Ubah spec** di dict `SPECS` (warna, teks, ukuran) lalu jalankan ulang.

