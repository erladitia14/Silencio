# Silencio — Generator SFX & Electric FX

Suara dan efek listrik generator Control Room 3. Dua modul **mandiri** yang saling terhubung
supaya efek & suara **selalu muncul bersamaan** — mustahil lepas sinkron.

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`BATTERY_PUZZLE.md`](BATTERY_PUZZLE.md) · [`ENEMY_AI.md`](ENEMY_AI.md) ·
> [`KNOCK_SYSTEM.md`](KNOCK_SYSTEM.md) · [`DAMAGE_EFFECT.md`](DAMAGE_EFFECT.md) ·
> [`KEY_SYSTEM.md`](KEY_SYSTEM.md) · [`SAFE_ZONE.md`](SAFE_ZONE.md)

> **Semua nama suara, tag, dan mekanisme di dokumen ini dibaca langsung dari Studio.**

---

## 📐 Arsitektur

```
ServerScriptService/
└── Aer/
    └── GeneratorSFXController      (1713 b)  ← Script tipis, menyalakan 2 modul

ReplicatedStorage/Modules/
├── GeneratorElectricFX             (16348 b) ← PENGENDALI efek listrik (SUMBER sinyal)
├── GeneratorSFX                    (14141 b) ← suara generator (PENGIKUT sinyal)
└── HighVoltage                     (BindableEvent) ← kanal penghubung
```

**Hubungannya:**

```
GeneratorElectricFX ──fire──► HighVoltage ──didengar──► GeneratorSFX
  (efek listrik muncul)         (di ReplicatedStorage)      (putar suara listrik)
```

Jadi setiap kali efek listrik muncul, `BindableEvent` **`HighVoltage`** di
`ReplicatedStorage` di-fire, dan `GeneratorSFX` langsung memutar
`high_voltage_electricity`. **Efek & suara tidak mungkin lepas sinkron.**

> `GeneratorSFX` **membuat** BindableEvent `HighVoltage` kalau belum ada — karena itu ia
> harus dimuat **lebih dulu** (lihat urutan di controller).

---

## 🔊 Peta Suara

| Momen | Suara |
|---|---|
| Tombol power ditekan | `pressing_a_large_industrial_button` |
| 4 baterai terpasang | `electrical_contacts` |
| Generator nyala — startup | `old_industrial_generator` |
| Generator nyala — loop mesin | `steady_industrial_generator` |
| Efek listrik muncul | `high_voltage_electricity` (one-shot, ikut sinyal efek) |

---

## ⚡ GeneratorElectricFX — efek listrik

**KONTRAK**: semua `ParticleEmitter` / `Beam` / `Trail` / `Light` yang di dalam objek
generator **dikelola modul ini**. Jangan menambah/mengubah efek di Explorer tanpa
menyadari kontrak ini — modul yang menyalakan & mematikannya.

Karakter efek: **tipis dan cepat** — `Lifetime` 0.1 s, `Speed` 0.2, `Size` maks **0.82**,
sehingga praktis tidak menghalangi pandangan pemain tapi tetap terasa "hidup".

| Parameter | Nilai |
|---|---|
| `RateMultiplier` | `1.0` (partikel per detik per emitter) |
| `Lifetime` | `NumberRange` ~0.1 s |
| `Size` | maks 0.82 |
| `Speed` | 0.2 |

Objek yang dicari: Model bernama **`Case`**, dan objek ber-tag **`AssemblySlot`**.
Attachment efek sudah disiapkan di dalam Attachment **`GeneratorSFX`** (dibuat tim).

---

## 🎚️ GeneratorSFX — suara

Mendengarkan sinyal & Attribute:

| Sumber | Dipakai untuk |
|---|---|
| `BindableEvent` **`HighVoltage`** (di `ReplicatedStorage`) | memicu suara listrik, sinkron dengan efek |
| Attribute **`BatteryPuzzleComplete`** pada objek tag **`BatteryCase`** | tahu puzzle baterai selesai |
| Attachment **`GeneratorSFX`** | titik pemasangan sound |
| Objek bernama **`ActiveButton`** | suara tombol |
| Tag **`AssemblySlot`** | memantau pemasangan panel/engine |

Modul ini juga mencari `Config` dari BatteryPuzzle (untuk konsistensi nama tag/attribute).

---

## 🔗 Jalur Integrasi Lengkap

| Dari | Ke | Lewat |
|---|---|---|
| `GeneratorElectricFX` | `GeneratorSFX` | `BindableEvent` **`HighVoltage`** |
| `PuzzleService` (BatteryPuzzle) | sistem lain | `BindableEvent` **`BatteryPuzzleCompleted`** |
| `GeneratorSFX` | generator | Attribute **`BatteryPuzzleComplete`** pada tag `BatteryCase` |
| `ActiveButtonService` | generator | Attribute **`GeneratorPowered`** |
| Klien | server | `RemoteEvent` **`BatteryPuzzleEvent`** di `ReplicatedStorage.Events` |

---

## ⚠️ Aturan Penting

1. **Jangan menyentuh script sistem lain.** Verbatim komentar controller:
   *"TIDAK menyentuh BatteryPuzzleController / AssemblyController / sistem lain."*
2. **Urutan pemuatan penting** — `GeneratorSFX` dulu (ia yang membuat `HighVoltage`),
   baru `GeneratorElectricFX`.
3. **Jangan tambah ParticleEmitter/Beam/Light baru** di objek generator tanpa tahu bahwa
   `GeneratorElectricFX` yang mengendalikannya — efekmu bisa tidak pernah menyala,
   atau menyala tanpa bisa dimatikan.
4. **Efek & suara sengaja diikat** lewat satu sinyal. Kalau butuh efek listrik tanpa suara,
   jangan lepas sinyalnya — matikan saja Sound-nya.

---

## 🐛 Catatan

- Aset suara (`pressing_a_large_industrial_button`, dst.) diambil **berdasarkan nama** dari
  `ReplicatedStorage.Modules.Audio` / objek suara di generator. Kalau nama diubah di Studio,
  suaranya akan **diam tanpa error** — cek dulu nama sebelum menyalahkan script.
- Kalau generator tidak bersuara sama sekali, periksa: (a) `HighVoltage` ada di
  `ReplicatedStorage`, (b) `GeneratorSFX` dimuat sebelum `GeneratorElectricFX`,
  (c) Attachment bernama `GeneratorSFX` benar-benar ada di model generator.
