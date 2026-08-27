# Silencio — Key System

Sistem progresi Chapter 1: **kunci → pintu ruang kontrol → power switch → lampu carnival**.

**Prinsip desain: versatile.** Tim cukup memberi **tag** (+ Attribute opsional) pada objek di
Studio. **Tidak perlu menempel script** dan **tidak perlu mengubah script inti.**

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`ENEMY_AI.md`](ENEMY_AI.md).

---

## 📐 Arsitektur

```
ServerScriptService/
└── KeySystemController        ← Script utama (orchestrator)
ReplicatedStorage/Modules/
└── KeySystem/                 ← Semua module
    ├── Config                 ← Nama tag, default, teks prompt
    ├── Signal                 ← Observer pattern ringan (BindableEvent)
    ├── KeyService             ← Siapa punya kunci apa (state kunci)
    ├── PowerService           ← Status listrik + daftar pintu terbuka
    ├── KeyPickupManager       ← Tag "KeyPickup"     → kasih kunci
    ├── DoorManager            ← Tag "LockedDoor"    → buka kalau punya kunci
    ├── SwitchManager          ← Tag "PowerSwitch"   → nyalakan power
    └── LightManager           ← Tag "CarnivalLight" → nyalakan lampu
```

Orchestrator **wajib** tetap Script di `ServerScriptService` — Script di `ReplicatedStorage`
tidak dijalankan engine. Yang ada di ReplicatedStorage hanya ModuleScript.

> **Modul di ReplicatedStorage terbaca client.** Source-nya (nama tag, KeyId default) bisa
> diintip player, jadi puzzle-nya *spoilable*. Tapi **bukan celah exploit**: seluruh state kunci
> & power hidup di server (`KeyService`, `PowerService`), dan prompt di-trigger lewat
> `ProximityPrompt.Triggered` yang divalidasi server. Kalau ingin benar-benar tersembunyi,
> pindahkan folder `KeySystem` ke `ServerStorage`.

Enemy AI ada di `ReplicatedStorage/Modules/EnemyController/` — lihat [`ENEMY_AI.md`](ENEMY_AI.md).

---

## 🎮 Alur Progresi

```
┌─────────────┐  ambil   ┌────────────┐  punya kunci  ┌──────────────┐
│  KeyPickup  │ ───────► │ KeyService │ ────────────► │  LockedDoor  │
└─────────────┘          └────────────┘               └──────┬───────┘
                                                             │ pintu terbuka
                                                             ▼
┌────────────────┐  PowerChanged(true)  ┌──────────────┐  ┌──────────────┐
│ CarnivalLight  │ ◄─────────────────── │ PowerService │◄─│ PowerSwitch  │
│  (semua nyala) │                      └──────────────┘  └──────────────┘
└────────────────┘
```

Semua modul **decoupled** lewat signal `PowerService`. `LightManager` tidak tahu apa-apa soal
kunci atau switch — dia cuma mendengar `PowerChanged`. Mau menambah reaksi lain saat power nyala
(suara, kabut, musik)? Subscribe ke signal yang sama, jangan sentuh modul lain.

---

## ⚙️ Setup Cepat

View → **Tag Editor**, lalu tempel tag berikut. Objek boleh berupa **BasePart** atau **Model**
(Model memakai `PrimaryPart`, atau BasePart pertama kalau `PrimaryPart` kosong).

| Tag | Ditempel pada | Efeknya |
|---|---|---|
| `KeyPickup` | kunci | muncul prompt "Ambil Kunci"; diambil → kunci masuk inventori tim, objek hilang |
| `LockedDoor` | pintu | prompt "Buka Pintu" (punya kunci) / "Terkunci — Butuh Kunci" (belum) |
| `PowerSwitch` | tuas/tombol | prompt "Nyalakan Power"; terkunci sampai pintu gate terbuka |
| `CarnivalLight` | lampu | ikut nyala/mati serempak mengikuti status power |

Tanpa Attribute apa pun, semuanya sudah nyambung: **semua id default `"control_room"`**.
Jadi 1 kunci + 1 pintu + 1 switch + beberapa lampu langsung jadi satu rantai puzzle yang jalan.

`ProximityPrompt` dibuat otomatis kalau belum ada. Kalau kamu sudah menaruh
`ProximityPrompt` sendiri di part itu, prompt milikmu yang dipakai (setting-mu tidak ditimpa,
kecuali `ActionText` yang memang dikelola sistem).

Objek yang **di-tag saat runtime** otomatis ikut terdaftar — tidak perlu restart.

### Tes cepat tanpa building

Spawn 4 Part, tag masing-masing `KeyPickup`, `LockedDoor`, `PowerSwitch`, `CarnivalLight`,
lalu Play. Ambil kunci → buka pintu → tekan switch → lampu menyala.

---

## 🔧 Attribute (opsional)

Semua Attribute di bawah ditaruh di **Properties objek ber-tag**, bukan di script.

### `KeyPickup`

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `KeyId` | String | `"control_room"` | Identitas kunci; harus cocok dengan `RequiredKey` pintunya |

### `LockedDoor`

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `DoorId` | String | `"control_room"` | Identitas pintu; dipakai `PowerSwitch` sebagai gate |
| `RequiredKey` | String | = `DoorId` | Kunci yang dibutuhkan; isi hanya kalau beda dari `DoorId` |
| `AutoClose` | Bool | `false` | Pintu menutup sendiri setelah dibuka |
| `AutoCloseDelay` | Number | `4` | Jeda auto-close (detik) |

### `PowerSwitch`

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `RequiresDoorOpen` | Bool | `true` | Butuh pintu gate terbuka dulu; `false` = switch bebas ditekan |
| `GateDoorId` | String | `"control_room"` | `DoorId` yang harus terbuka |

### `CarnivalLight`

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `OnBrightness` | Number | `2` | Brightness saat menyala |
| `OffBrightness` | Number | `0` | Brightness saat mati |

### Contoh: dua puzzle terpisah

```
Kunci Gudang     : KeyPickup,   KeyId = "gudang"
Pintu Gudang     : LockedDoor,  DoorId = "gudang"
Switch Gudang    : PowerSwitch, GateDoorId = "gudang"

Kunci Kontrol    : KeyPickup,   KeyId = "control_room"   (default, boleh dikosongkan)
Pintu Kontrol    : LockedDoor,  DoorId = "control_room"  (default, boleh dikosongkan)
```

### Contoh: satu master key membuka banyak pintu

```
Kunci Master     : KeyPickup,  KeyId = "master"
Pintu A          : LockedDoor, DoorId = "gudang",       RequiredKey = "master"
Pintu B          : LockedDoor, DoorId = "control_room", RequiredKey = "master"
```

`DoorId` tetap berbeda (supaya switch bisa mensyaratkan pintu tertentu), tapi keduanya
dibuka oleh kunci yang sama.

---

## 🧠 Perilaku yang perlu diketahui

**Kunci itu milik TIM, bukan per-player.** Begitu satu player mengambil kunci, seluruh tim
bisa membuka pintunya, dan kunci tetap dimiliki walau player itu keluar dari game. Ini sengaja
— game-nya co-op. Ubah `KeyService` kalau mau per-player.

**Objek `KeyPickup` di-`Destroy()` setelah diambil.** Kunci hilang dari dunia untuk semua
player, jadi tidak bisa diambil dua kali.

**"Membuka pintu" = `Transparency = 1` + `CanCollide = false`.** Belum ada animasi pintu
berputar. Nilainya bisa diubah di `Config.DoorOpenTransparency` / `Config.DoorOpenCanCollide`.
Properti asli disimpan sebelum diubah, jadi `AutoClose` mengembalikannya dengan benar.

**Pintu terkunci tetap menampilkan prompt.** Teksnya "Terkunci — Butuh Kunci" dan tekanannya
tidak melakukan apa-apa. Ini feedback yang disengaja, bukan bug — player tahu pintu itu memang
tujuan, bukan dekorasi.

**Prompt pintu update sendiri saat kunci didapat.** Teks berubah dari "Terkunci" ke
"Buka Pintu" tanpa player harus menjauh dan mendekat lagi.

**Power tidak bisa dimatikan lagi lewat switch.** Setelah `PowerChanged(true)`, prompt switch
di-disable permanen. Kalau butuh switch on/off, tambahkan cabang toggle di `SwitchManager`.

**`CarnivalLight` menangani dua bentuk objek.** Kalau yang di-tag adalah objek `Light`
(`PointLight`/`SpotLight`/`SurfaceLight`) → `Enabled` + `Brightness` diatur langsung. Kalau
`BasePart` → semua child `Light`-nya diatur, **dan** part-nya jadi `Neon` + warna hangat
(`Config.LightOnColor`) saat nyala, lalu kembali ke Material/Color asli saat mati.

---

## 🚧 Yang belum ada (jujur)

| Belum ada | Konsekuensi |
|---|---|
| Animasi pintu | Pintu "hilang" (transparan), bukan berayun terbuka |
| Suara | Tidak ada SFX kunci diambil / pintu terbuka / power menyala |
| GUI / notifikasi | Player tahu progresi hanya dari teks prompt |
| Persistensi (DataStore) | Progresi hilang saat server restart |
| Switch off | Power sekali nyala, tidak bisa dimatikan |
| Multi-part door | Hanya `PrimaryPart` yang jadi transparan & non-collide. Pintu Model banyak-part → **set `PrimaryPart`** ke daun pintunya, atau `Union` jadi satu part |

Semua ini bisa ditambah tanpa menyentuh modul lain: subscribe `PowerService.PowerChanged` /
`PowerService.DoorStateChanged` dari script baru.

---

## 🐛 Jebakan

- **Lupa set `PrimaryPart` pada Model pintu** → part yang terbuka bisa jadi part acak
  (BasePart pertama). Set `PrimaryPart` secara eksplisit.
- **Objek ber-tag tanpa BasePart sama sekali** (mis. Folder atau Model kosong) → di-skip dengan
  `warn` di Output, bukan error. Cek Output kalau ada objek yang tidak bereaksi.
- **`RequiredKey` salah ketik** → pintu tidak akan pernah bisa dibuka dan tidak ada warning
  (sistem tidak bisa tahu KeyId mana yang "valid"). Cocokkan persis dengan `KeyId` kuncinya.
- **`RequiresDoorOpen` mengacu `DoorId`, bukan nama objek.** Kalau switch tidak pernah unlock,
  cek `GateDoorId` switch == `DoorId` pintu.
- **Perubahan ModuleScript tidak berlaku pada sesi Play yang sudah jalan** (`require` di-cache) —
  Stop dulu, lalu Play ulang.

---

## ✅ Status verifikasi

Diverifikasi statis di Studio (edit mode) pada 27 Agustus 2026:

- 9/9 source di Studio **identik byte-per-byte** dengan file lokal
- 8/8 modul lolos `pcall(require)` dari path `ReplicatedStorage.Modules.KeySystem`
- 29/29 behavioral test standalone: resolusi BasePart/Model/PrimaryPart, fallback tiap
  Attribute, alur penuh kunci→pintu→switch→power, penanganan child `Light` vs non-`Light`
- 54/54 cek struktural lokal (balance Lua, path require, nol referensi service hardcode)

**Belum playtest** — perilaku runtime `ProximityPrompt` (jarak aktivasi, hold duration,
`Triggered` di multiplayer) harus dicek dengan Play.

Riwayat perubahan: lihat [`PROGRESS.md`](PROGRESS.md).
