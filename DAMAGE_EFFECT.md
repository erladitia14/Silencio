# Silencio — DamageEffect (efek horor saat dikejar)

`LocalScript` di `StarterCharacterScripts/DamageEffect` — efek **sinematik horor** yang
menguat seiring monster mendekat. **Aktif otomatis, tanpa tag, tanpa konfigurasi.**

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`ENEMY_AI.md`](ENEMY_AI.md) · [`KNOCK_SYSTEM.md`](KNOCK_SYSTEM.md) ·
> [`BATTERY_PUZZLE.md`](BATTERY_PUZZLE.md) · [`GENERATOR_SFX.md`](GENERATOR_SFX.md) ·
> [`KEY_SYSTEM.md`](KEY_SYSTEM.md) · [`SAFE_ZONE.md`](SAFE_ZONE.md)

> **Semua angka di dokumen ini dibaca langsung dari Studio** (versi Studio lebih baru dari
> repo — lihat tabel drift di [`README.md`](README.md)).

---

## Cara Kerja

Monster dicari lewat tag **`Monster`** (`CollectionService`), jadi **mendukung banyak monster
sekaligus** — yang mengendalikan efek adalah monster **terdekat yang masih hidup**.
Scan dilakukan `SCAN_INTERVAL` = **0.1 detik** (10×/detik), bukan tiap frame.

Jarak dihitung lewat fungsi **`effectiveDistance`** yang mengompensasi tinggi monster raksasa
(mis. Clown), supaya intensitas benar-benar mencapai 100% saat monster menempel — bukan
mentok di 60% karena monster tinggi.

Intensitas dasar: `math.clamp(1 - (jarak / START_DIST), 0, 1)`.

---

## Efek & Ambangnya

| Efek | Ambang | Detail |
|---|---|---|
| **Vignette 4-sisi** | mulai `START_DIST` = **65** stud | Gradien hitam & merah tua di sekeliling layar, `math.noise` — **tanpa gambar eksternal** |
| **`UiDikejar`** — overlay dikejar | ikut `START_DIST` | `ScreenGui` dengan `IgnoreGuiInset` (aman **HP/mobile**); saat intensitas penuh: Background **0.85**, dengung **0.5**, "bcak" **0.5** |
| **Getar kamera** | ikut `START_DIST` | Guncangan halus, maks `MAX_SHAKE` = **0.11 rad**, frekuensi `SHAKE_SPEED` = **11** |
| **Denyut jantung** | `PULSE_DIST` = **25** stud | Vignette berdenyut seirama detak, makin cepat makin dekat |
| **Blur adrenalin** | `BLUR_DIST` = **12** stud | `Lighting.BlurEffect`, maks `MAX_BLUR` = **10** |
| **Flash darah tengah** | saat intensitas tinggi | `Frame` **`CenterBloodFlash`** di tengah layar |

---

## Instance yang Dibuat

| Nama | Kelas | Lokasi |
|---|---|---|
| `SilencioHorrorCinematic` | — | penanda efek utama |
| `SilencioHorrorVignetteGui` | `ScreenGui` | PlayerGui |
| ├── `VignetteContainer` | `Frame` | berisi 4 sisi vignette + `UIGradient` |
| └── `CenterBloodFlash` | `Frame` | kilatan darah tengah |
| **`UiDikejar`** | `ScreenGui` | PlayerGui — overlay dikejar (IgnoreGuiInset) |
| `SilencioHorrorAdrenalineBlur` | `BlurEffect` | `Lighting` |

---

## Konstanta Lengkap

```lua
local MONSTER_TAG     = "Monster"

local START_DIST      = 65    -- jarak mulai terasa bayangan, getar, dan UiDikejar aktif (studs)
local PULSE_DIST      = 25    -- jarak mulai berdenyut jantung (studs)
local BLUR_DIST       = 12    -- jarak penglihatan mengabur (studs)
local MAX_SHAKE       = 0.11  -- guncangan maksimum halus (radians)
local SHAKE_SPEED     = 11    -- frekuensi getar mengalir
local MAX_VIGNETTE    = 0.82  -- kepekatan maksimum vignette
local MAX_BLUR        = 10    -- tingkat blur saat monster menempel
local SCAN_INTERVAL   = 0.1   -- detik; scan monster terdekat 10x/detik

local RENDER_NAME     = "SilencioHorrorCinematic"
local BLUR_NAME       = "SilencioHorrorAdrenalineBlur"
local GUI_NAME        = "SilencioHorrorVignetteGui"
local UI_DIKEJAR_NAME = "UiDikejar"
```

> Nilai-nilai ini **hardcoded di script** (bukan di Config). Kalau mau tuning, ubah di sini —
> dan **ingat**: versi Studio lebih baru dari repo, jadi edit di Studio dulu.

---

## Fungsi Internal

| Fungsi | Tugas |
|---|---|
| `makeVigFrame` | Bikin satu sisi vignette (dipakai 4×) |
| `effectiveDistance` | Jarak terkoreksi tinggi monster — inti akurasi intensitas |
| `nearestMonsterRoot` | Cari monster terdekat yang masih hidup (tag `Monster`) |
| `onRender` | Loop utama: hitung intensitas → aplikasikan semua efek |
| `cleanup` | Bersihkan instance saat karakter hilang/respawn |

---

## ⚠️ Catatan Drift (penting)

`DamageEffect` adalah salah satu file yang **versi Studio-nya jauh lebih baru** dari repo:

| | Repo (`src/`) | **Studio** |
|---|---|---|
| Ukuran | 10.023 byte | **14.481 byte** |
| `START_DIST` | 22 | **65** |
| `PULSE_DIST` | 13 | **25** |
| `BLUR_DIST` | 8 | **12** |
| `UiDikejar` | ❌ belum ada | ✅ ada |

**Dokumen ini mencatat versi Studio.** Kalau menyalin ke repo, ambil dari Studio dulu.

---

## Hubungan dengan Sistem Lain

- **Enemy AI** — efek bergantung pada tag `Monster`. Monster tanpa tag tidak memicu efek.
  → [`ENEMY_AI.md`](ENEMY_AI.md)
- **Knock & Revive** — saat pemain tumbang, efek ini **tetap** berjalan (monster masih dekat),
  yang justru memperkuat suasana panik. → [`KNOCK_SYSTEM.md`](KNOCK_SYSTEM.md)
- **Safe Zone** — saat pemain bersembunyi di bilik, monster tidak bisa menarget, tapi efek ini
  **murni berbasis jarak** — kalau monster berdiri dekat bilik, efeknya masih terasa. Itu
  memang disengaja (teror "monster mengendus di luar").
