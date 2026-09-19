# Kredit & Lisensi — Mesh Baterai 3D

Aset untuk mini games **Control Room 3** (shape matching baterai).
Sumber: [Poly Pizza](https://poly.pizza) — agregator model low-poly, tanpa login.

**Tanggal unduh:** 15 Sep 2026
**Lokasi file:** `assets/battery_meshes/*.glb`

---

## ⚠️ PENTING — BACA DULU

Dari 13 model yang diunduh, **hanya 4 yang CC0 (bebas total)**. Sisanya **9 model CC-BY 3.0**,
yang artinya **BOLEH dipakai komersial TAPI WAJIB mencantumkan kredit** ke pembuatnya.

**CC-BY 3.0 bukan masalah untuk game komersial** — tidak ada klausa ShareAlike, tidak ada
batasan komersial. Syaratnya cuma satu: nama pembuat harus disebutkan di suatu tempat yang
wajar (kredit game, deskripsi game, atau layar credits).

**Rekomendasi:** kalau mau nol ribet, pakai **4 model CC0** saja (bisa dipakai tanpa kredit).
Tapi karena shape matching butuh banyak bentuk berbeda, 4 model mungkin kurang. Pakai CC-BY
+ tulis kredit di bawah ini = aman.

---

## Model CC0 — Bebas Dipakai, Tanpa Kredit

| File | Nama | Pembuat |
|---|---|---|
| `baterai_AA_quaternius.glb` | Battery | Quaternius |
| `baterai_AA_quaternius_2.glb` | Battery | Quaternius |
| `baterai_hatmyguy.glb` | Battery | hat_my_guy |
| `baterai_power_cell.glb` | Sci Fi Wall Power Cell | Dipper98 |

## Model CC-BY 3.0 — Wajib Kredit

| File | Nama | Pembuat | Sumber |
|---|---|---|---|
| `baterai_AA_silinder.glb` | AA battery | Poly by Google | [link](https://poly.pizza/m/2TKK0wpiWPw) |
| `baterai_6V_kotak.glb` | 6v Batteries | Jarlan Perez | [link](https://poly.pizza/m/6lL1xaadlw0) |
| `baterai_aki_mobil.glb` | Car Battery | J-Toastie | [link](https://poly.pizza/m/hLVNyFYOOX) |
| `baterai_tabung_energi.glb` | Energy Canister | Nick Slough | [link](https://poly.pizza/m/3ohugtTcUR) |
| `baterai_pack.glb` | Batteries | sirkitree | [link](https://poly.pizza/m/7MuOxWpZY9c) |
| `baterai_zeoxo.glb` | Battery | zeoxo | [link](https://poly.pizza/m/9dtxNKBIhAW) |
| `baterai_bruno.glb` | Battery | Bruno Oliveira | [link](https://poly.pizza/m/9gnjbN0VUUn) |
| `baterai_poly_google.glb` | Battery | Poly by Google | [link](https://poly.pizza/m/8Ggl5vpgUR_) |
| `baterai_AA_pasangan.glb` | AA Batteries | Jarlan Perez | [link](https://poly.pizza/m/fRK0XAb8Jmb) |

---

## Teks Kredit Siap Tempel

Taruh di **deskripsi game Roblox** atau layar credits:

```
3D Assets:
"Battery", "AA battery", "6v Batteries", "Car Battery", "Energy Canister",
"Batteries", "AA Batteries", "Sci Fi Wall Power Cell"
via poly.pizza — CC0 / CC-BY 3.0
Creators: Quaternius, hat_my_guy, Dipper98, Poly by Google,
Jarlan Perez, J-Toastie, Nick Slough, sirkitree, zeoxo, Bruno Oliveira
```

Atau versi ringkas:
```
Battery 3D models by Quaternius, Poly by Google, Jarlan Perez,
J-Toastie, Nick Slough, sirkitree, zeoxo, Bruno Oliveira, hat_my_guy, Dipper98
(poly.pizza — CC0 / CC BY 3.0)
```

---

## Detail Teknis Mesh

Semua file **GLB valid (glTF 2.0)**, low-poly — cocok untuk Roblox:

| File | Ukuran | Triangle | Mesh/Node |
|---|---|---|---|
| `baterai_AA_silinder.glb` | 14 KB | ~260 | 1/1 |
| `baterai_AA_quaternius.glb` | 11 KB | ~132 | 1/2 |
| `baterai_AA_quaternius_2.glb` | 9 KB | ~100 | 1/2 |
| `baterai_hatmyguy.glb` | 43 KB | ~604 | 1/2 |
| `baterai_6V_kotak.glb` | 39 KB | ~728 | 1/1 |
| `baterai_aki_mobil.glb` | 36 KB | ~478 | 1/2 |
| `baterai_tabung_energi.glb` | 37 KB | ~486 | 1/2 |
| `baterai_power_cell.glb` | 33 KB | ~396 | 10/10 |
| `baterai_pack.glb` | 26 KB | ~280 | 2/2 |
| `baterai_zeoxo.glb` | 19 KB | ~212 | 3/3 |
| `baterai_bruno.glb` | 23 KB | ~372 | 1/1 |
| `baterai_poly_google.glb` | 139 KB | ~3.920 | 4/4 |
| `baterai_AA_pasangan.glb` | 19 KB | ~320 | 1/1 |

**Total: 13 model, ~8.300 triangle, ~450 KB.**

Semua jauh di bawah batas Roblox. Yang paling berat `baterai_poly_google.glb` (3.920 tri) —
masih aman, tapi kalau dipakai banyak copy di map, pertimbangkan decimate.

---

## Cara Impor ke Roblox Studio

**Opsi A — 3D Importer (paling gampang):**
1. Di Studio: **View → Asset Manager**
2. Klik **Bulk Import** → **3D Models**
3. Pilih semua `.glb` di folder `assets/battery_meshes/`
4. Roblox otomatis konversi ke MeshPart

**Opsi B — Drag & drop:**
Langsung drag file `.glb` dari Windows Explorer ke viewport Studio.

**Opsi C — MCP `upload_asset`:**
Upload per file via tool MCP (kalau mau otomatis).

**Catatan:** GLB dengan material (semua model di sini punya 1–4 material) akan masuk sebagai
MeshPart + SurfaceAppearance. Warnanya dari material GLB — **untuk shape matching, lu mungkin
mau overwrite warna** jadi warna solid per bentuk biar kontras jelas.

---

## Catatan Riset

- Lisensi dicek langsung dari halaman Poly Pizza masing-masing model (bukan dari deskripsi
  pencarian) — karena label pencarian tidak selalu akurat.
- **Koreksi:** sebelumnya sempat gua sebut semua model ini "CC0" — itu **salah**. Setelah dicek
  per-halaman, hanya 4 yang CC0; 9 lainnya CC-BY 3.0.
- Data mentah lisensi ada di `LISENSI.json` di folder yang sama.

---

## Aset Genset & Bahan Bakar (19 Sep 2026) — alur "starter genset"

Untuk mekanik: kumpulin baterai → isi aki genset → isi bensin → start genset.

| File | Judul | Pembuat | Lisensi | Tris | Wajib kredit? |
|------|-------|---------|---------|------|---------------|
| `aki_genset.glb` | Car Battery | J-Toastie | CC-BY 3.0 | 478 | YA |
| `jerigen_bensin.glb` | Gas Can | Quaternius | **CC0** | 788 | tidak |
| `genset.glb` | Generator (kecil) | KolosStudios | CC-BY 3.0 | 478 | YA |
| `genset_besar.glb` | Large Electric Generator | miro_art_studio | CC-BY 3.0 | 15.874 | YA |

Sumber: Poly Pizza (tanpa login). Semua GLB glTF 2.0 valid, texture belum embed
(warna dari material — bisa di-overwrite di Studio).

**Halaman sumber (kalau mau download manual / cek lisensi):**
- Car Battery: https://poly.pizza/m/hLVNyFYOOX
- Gas Can (CC0): https://poly.pizza/m/jRymgnHTTb
- Generator kecil: https://poly.pizza/m/K58RQ63qR5
- Large Generator: https://poly.pizza/m/ZPlQHwiqTp

**Catatan:** `genset_besar.glb` 15.874 tris — dua kali lipat sisanya. Kalau dipakai
cuma 1 di map, aman. `genset.glb` (478 tris) lebih ringan kalau mau yang simpel.
