# Silencio — The Dark Story

Game horror co-op escape di karnaval terbengkalai, dibuat dengan Roblox Studio.

**Chapter 1: The Mask Maze** — puzzle trivia + topeng & lukisan, dijaga monster.

---

## 📚 Dokumentasi Sistem

| Sistem | Dokumen | Isi singkat |
|---|---|---|
| **Enemy AI** | [`ENEMY_AI.md`](ENEMY_AI.md) | NPC monster FSM: patrol, chase, attack, animasi otomatis, pola driver+skin untuk mesh import |
| **Key System** | [`KEY_SYSTEM.md`](KEY_SYSTEM.md) | Progresi kunci → pintu → power switch → lampu carnival |

Riwayat perubahan & hasil verifikasi tiap sistem: [`PROGRESS.md`](PROGRESS.md).

---

## 🗂️ Struktur Kode

```
src/
├── ServerScriptService/                 ← Script (server, jalan otomatis)
│   ├── EnemyController.server.luau      ← orchestrator Enemy AI
│   └── KeySystemController.server.luau  ← orchestrator Key System
├── ReplicatedStorage/Modules/           ← ModuleScript (logika, di-require)
│   ├── EnemyController/                 ← 10 module Enemy AI
│   └── KeySystem/                       ← 8 module Key System
└── ServerStorage/
    └── NPCAnimationTemplate.server.luau ← contoh opsional animasi berlogika
```

**Pola yang dipakai kedua sistem sama:** satu `Script` orchestrator di `ServerScriptService`
yang me-`require` folder ModuleScript-nya di `ReplicatedStorage/Modules/`.

Kenapa `Script`-nya harus di `ServerScriptService`: `Script` di `ReplicatedStorage` tidak
dijalankan engine. Kenapa modulnya di `ReplicatedStorage`: satu tempat berkumpul untuk semua
module, dan client bisa me-`require` kalau nanti ada kebutuhan UI.

> **Konsekuensi:** isi `ReplicatedStorage` **terbaca player**. Source module jadi bisa diintip
> (nama tag, nilai default). Bukan celah exploit — semua state & keputusan hidup di server —
> tapi kalau ada sistem yang isinya harus benar-benar rahasia, taruh di `ServerStorage`.

---

## 🏷️ Semua Tag dalam Satu Tabel

Kedua sistem digerakkan **CollectionService tag** — tempel di View → **Tag Editor**,
tanpa menempel script.

| Tag | Sistem | Ditempel pada |
|---|---|---|
| `Monster` | Enemy AI | Model NPC (rig ber-`Humanoid`) |
| `MonsterSkin` | Enemy AI | Model mesh visual (pola driver+skin) |
| `SafeZone` | Enemy AI | Part area aman; player di dalamnya tidak ditarget |
| `KeyPickup` | Key System | Kunci yang bisa diambil |
| `LockedDoor` | Key System | Pintu yang butuh kunci |
| `PowerSwitch` | Key System | Tuas/tombol power |
| `CarnivalLight` | Key System | Lampu yang menyala saat power on |

Detail Attribute per tag ada di dokumen sistem masing-masing.

---

## 🔄 Alur Lokal → Studio

**Folder lokal ini = source of truth.** Rojo **tidak dipakai lagi**; sinkronisasi ke Studio
dilakukan lewat MCP Roblox Studio (`set_script_source`).

Artinya: kalau kamu mengedit script langsung di Studio, **salin balik ke folder ini**, atau
perubahanmu akan tertimpa pada push berikutnya.

`default.project.json` dan `aftman.toml` masih ada di repo sebagai artefak Rojo lama — sudah
tidak dipakai, jangan dijadikan acuan.

---

## ✅ Status

| Sistem | Kode | Di Studio | Verifikasi statis | Playtest |
|---|---|---|---|---|
| Enemy AI | ✅ | ✅ | ✅ | sebagian (lihat PROGRESS.md) |
| Key System | ✅ | ✅ | ✅ | ❌ belum |

**Belum ada di kedua sistem:** suara, GUI/notifikasi, dan persistensi DataStore
(progresi hilang saat server restart).

---

## 🐛 Jebakan Lintas Sistem

- **`require` di-cache per sesi Play.** Mengubah ModuleScript saat sesi Play sedang jalan tidak
  berefek. Stop dulu, lalu Play ulang.
- **Objek ber-tag tanpa BasePart** (Folder / Model kosong) di-skip dengan `warn` di Output,
  bukan error. Kalau ada objek yang tidak bereaksi, cek Output dulu sebelum menyalahkan script.
- **Prinsip "satu penyetir".** Hanya satu sistem yang boleh menyetir `Animator`/`Humanoid`
  sebuah NPC. Dua penyetir = animasi kejang. Ini akar beberapa bug lama.
