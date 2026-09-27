# Silencio — Knock & Revive System

Sistem **co-op down state**: pemain yang dipukul monster **tumbang** (bukan langsung mati),
merangkak pelan, dan harus **dibangunkan rekan** sebelum bleed-out habis.

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`ENEMY_AI.md`](ENEMY_AI.md) · [`KEY_SYSTEM.md`](KEY_SYSTEM.md) ·
> [`SAFE_ZONE.md`](SAFE_ZONE.md) · [`BATTERY_PUZZLE.md`](BATTERY_PUZZLE.md) ·
> [`DAMAGE_EFFECT.md`](DAMAGE_EFFECT.md) · [`GENERATOR_SFX.md`](GENERATOR_SFX.md)

> ⚠️ **Sistem ini MILIK TIM, bukan punya Aer.** Dulu ada DUA sistem knock paralel di project
> ini — KnockSystem milik Aer (`ReplicatedStorage.Modules.KnockSystem` + `KnockController` +
> `KnockUI` + `RevivePromptFilter`) dan `ReviveManager` milik Tim. Keduanya aktif bersamaan,
> dan **sistem Tim selalu menang**: ia men-set `Health = 1` di dalam handler `HealthChanged`
> sebelum sistem Aer sempat melihat kondisi lethal, jadi `DownedState.enter` milik Aer tidak
> pernah jalan. KnockSystem milik Aer **sudah DIHAPUS 23 Sep 2026**. Jangan dihidupkan lagi.

> **Semua angka di dokumen ini dibaca langsung dari Studio** (bukan file lokal repo).
> Sumber: `ReplicatedStorage.SilencioHoror.Config.Revive`.

---

## Alur Singkat

1. Monster ber-tag `Monster` menyerang → HP pemain habis.
2. `ReviveManager` (server) mencegat `HealthChanged <= 0` → **`Health = 1`** (anti-death) +
   `KnockPlayer(player)`.
3. Pemain tumbang → Attribute **`IsKnocked`** = `true` di karakter.
4. Pemain **merangkak** (`CrawlSpeed` = **3.5**, jump dimatikan), Tool yang dipegang di-drop,
   pose merangkak dipasang. Animasi: `rbxassetid://101410159389643` (Silencio Horror).
5. **Bleed-out 45 detik.** Kalau habis → `EliminatePlayer` → mode **spectate**.
6. Rekan datang (≤ **12 stud**) → prompt **"Revive Teammate"** → **tahan 10 detik** →
   HP jadi **50**.
7. Self-revive tersedia kapan saja lewat Developer Product **49 R$**.

---

## 📐 Arsitektur

```
ServerScriptService/
└── SilencioServer/                     ← framework TIM
    ├── ReviveManager                   ← OTAK: cegat fatal damage, bleed-out, revive, marketplace
    ├── InteractionManager              ← validasi jarak interaksi
    └── (Network, PlayerManager, ...)   ← sisa framework

StarterPlayer/StarterPlayerScripts/
└── SilencioClient/
    ├── ReviveController                ← HUD darah, overlay tumbang, prompt revive, pose merangkak
    ├── SpectateController              ← mode tonton setelah eliminasi
    └── CustomPromptController          ← billboard prompt "Revive Teammate"

ReplicatedStorage/
└── SilencioHoror/Config                ← semua tuning (tabel `Revive`)
```

**Tidak ada folder modul khusus** — sistem ini menyatu di dalam framework `SilencioServer` /
`SilencioClient` milik Tim. Karena itu **jangan buat folder `KnockSystem` baru**; kalau perlu
mengubah perilaku, ubah `Config.Revive` atau koordinasi dengan Tim.

---

## 🔌 Kontrak Data

### Attribute di karakter (replikasi otomatis — client tidak butuh remote)

| Attribute | Tipe | Isi |
|---|---|---|
| **`IsKnocked`** | Bool | `true` = sedang tumbang |
| **`IsDead`** | Bool | `true` = sudah tereliminasi (mode spectate) |

### Remote (dibuat oleh `Network` dari `SilencioHoror.Config`)

| Remote | Jenis | Arah | Isi |
|---|---|---|---|
| `PlayerKnocked` | Event | server → semua client | `(player, bleedoutDuration)` |
| `PlayerRevived` | Event | server → semua client | `(targetPlayer, reviver, isSelfRevive)` |
| `PlayerDiedPermanently` | Event | server → semua client | `(player)` |
| `TeammateReviveComplete` | Event | client → server | `(targetPlayer)` |
| `SpectateRespawnSuccess` | Event | server → client | — |
| `PromptSelfRevive` | Function | client → server | konfirmasi self-revive |
| `PromptSpectateRespawn` | Function | client → server | konfirmasi respawn berbayar |

---

## ⚙️ Konfigurasi (`SilencioHoror.Config.Revive`)

| Field | Default | Arti |
|---|---|---|
| `BleedOutDuration` | 45 | Detik sebelum mati permanen |
| `CrawlSpeed` | 3.5 | WalkSpeed saat merangkak (normal 16) |
| `RevivedHealth` | 50 | HP setelah dibangunkan rekan |
| `SelfReviveHealth` | 100 | HP setelah self-revive (beli) |
| `TeammateReviveDuration` | 10 | Detik menahan prompt revive |
| `ReviveInteractDistance` | 12 | Jarak maksimum revive (stud) |
| `SelfRevivePrice` | 49 | Harga self-revive (R$) |
| `SelfReviveProductId` | 3714758114 | Developer Product self-revive |
| `SpectateRespawnPrice` | 119 | Harga respawn dari spectate (R$) |
| `SpectateRespawnProductId` | 3714758147 | Developer Product respawn |
| `KnockAnimationId` | `rbxassetid://101410159389643` | Animasi merangkak |

---

## 🖥️ Sisi Klien

### `ReviveController` (`SilencioClient`)

- **HUD** — `DynamicHealthContainer` ("HEALTH: n / 100", muncul hanya saat < 100%) +
  overlay `KnockedOverlay` (`FullBloodTint`, bar bleed-out, tombol self-revive).
- **Saat tumbang** — pasang pose merangkak, WalkSpeed 3.5, tampilkan overlay.
- **Saat revive** — lepas pose, WalkSpeed 12, HP = 100 (self) atau 50 (rekan).
- **Prompt rekan** — pasang attribute di HRP pemain tumbang (`InteractDistance` 12,
  `HoldDuration` 10, `PromptScale` 1.25) lalu `CustomPrompt.Register(hrp, "Revive Teammate")`.
  Saat prompt ditrigger → `TeammateReviveComplete:FireServer(targetPlayer)`.

### `SpectateController` (`SilencioClient`)

Setelah `PlayerDiedPermanently`: pemain masuk mode tonton, label `"Status: Knocked (Bleeding Out)"`
untuk rekan, tombol respawn berbayar (119 R$).

---

## 🤝 Hubungan dengan Enemy AI

`TargetFinder:isValidTarget` menolak karakter yang tumbang supaya monster melepas korban dan
mencari target lain. Karena **historis ada dua sistem knock**, ia membaca KEDUA Attribute:

```lua
if character:GetAttribute("Knocked") == true then return false end    -- KnockSystem Aer (sudah dihapus)
if character:GetAttribute("IsKnocked") == true then return false end  -- ReviveManager TIM (aktif)
```

Cek `IsKnocked` adalah yang benar-benar bekerja di place `Script`. Kalau salah satu terlewat,
monster akan tetap mengejar pemain yang sedang tumbang.

> **Status place `BUILD Chapter 1`:** versi `TargetFinder` di sana belum punya cek ini
> (menunggu perintah Aer). Jadi di BUILD monster masih mengejar pemain tumbang.

> **Jangan bergantung pada `AISignal`.** Sistem knock lama (Aer) memutuskan knock dari
> `BindableEvent` `AISignal` milik monster. Sistem TIM **tidak** — ia mencegat `HealthChanged`,
> jadi knock tetap terjadi walau script NPC tidak meng-emit event apa pun.

---

## 🧪 Cara Menguji

`SilencioServer` menyediakan API test global (dibuat saat server start):

```lua
_G.TestKnock(player)     -- paksa pemain tumbang
_G.TestRevive(player)    -- paksa revive
_G.TestDummy(player)     -- spawn dummy rekan tumbang untuk latihan revive
_G.TestSpectate(player)  -- eliminasi pemain -> mode spectate
_G.TestDamage(amount, player)
```

Harness ad-hoc: `_tools/verify_knock.lua` (integrasi — place-agnostic) dan
`_tools/verify_build.lua` (status place BUILD). Jalankan lewat `_tools/mcp.py`:

```bash
cd _tools && python -c "import mcp,pathlib;print(mcp.luau(pathlib.Path('verify_knock.lua').read_text(encoding='utf-8'), instance_id='instance:93u-cgu'))"
```

---

## 🐛 Riwayat Bug — bleed-out tidak pernah membunuh (DIPERBAIKI 23 Sep 2026)

**Gejala:** pemain tumbang **tidak pernah** mati walau bleed-out habis — tumbang selamanya,
HP malah naik pelan (regen legacy +1/detik).

**Akar masalah:** `EliminatePlayer` dipanggil DARI DALAM `BleedoutThread` (thread `task.delay`
di `KnockPlayer`), lalu fungsi itu memanggil `task.cancel(info.BleedoutThread)` — yaitu
**membatalkan thread dirinya sendiri**. `task.cancel` menghentikan eksekusi seketika, jadi
semua baris di bawahnya (`IsDead = true`, `Health = 0`, fire remote) tidak pernah jalan.

**Fix** (di `ReviveManager.EliminatePlayer`):

```lua
if info and info.BleedoutThread and info.BleedoutThread ~= coroutine.running() then
    task.cancel(info.BleedoutThread)
end
```

`coroutine.running()` di dalam callback `task.delay` identik dengan thread yang dikembalikan
`task.delay`, jadi penjaga ini mendeteksi "saya sedang berjalan di dalam thread ini".

**Hasil verifikasi:**

| Uji | Sebelum | Sesudah |
|---|---|---|
| Bleed-out habis → mati | ❌ `isDead=false`, HP 100 | ✅ `isDead=true`, HP 0 |
| Revive membatalkan bleed-out | — | ✅ tetap hidup |
| Self-revive (durasi 45s) | — | ✅ HP 100, walk 12 |
| Thread lama tidak membunuh belakangan | — | ✅ tetap hidup |
| Tumbang lagi setelah revive → mati | — | ✅ mati normal |

> **Pelajaran umum:** `task.cancel(thread)` menghentikan eksekusi seketika — **termasuk thread
> yang sedang berjalan**. Jangan pernah `task.cancel` thread milik fungsi yang bisa dipanggil
> dari dalam thread itu sendiri. Jebakan ini tidak terlihat dari membaca kode; harus dijalankan.

> **Catatan:** `ReviveManager` milik Tim dan **tidak ada di repo Git** (framework Tim tidak
> di-track), jadi fix ini hanya hidup di Studio. Kalau place BUILD belum menerimanya, bug yang
> sama masih ada di sana.
