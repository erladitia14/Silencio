# 📋 PROGRESS — Silencio "The Dark Story"

> Game horror co-op Roblox · KARIS Studio × OnBlox Studio
> Target rilis: **akhir September 2026** · Chapter 1: *The Mask Maze*
>
> **Aturan catat progress:** file ini HANYA di-update ketika Aer bilang "catat progress".
> Setiap perintah = **1 entri baru yang merangkum progres turn itu secara keseluruhan**.
> Bukan otomatis, bukan dipecah per-fitur kecil. Entri terbaru di atas.

---

## Konvensi

- **Source of truth:** folder lokal `C:\Users\erlan\Documents\Silencio` (Rojo) → di-push ke Studio.
- **Repo:** `erladitia14/Silencio` (private) · branch `main`.
- **Verifikasi tanpa playtest:** struktural + compile-check Studio + behavioral test. Playtest = Aer.

---

## 🗓️ Log Progress

### Entri #2 — Relokasi modules Monster AI → `ReplicatedStorage/Modules/EnemyController`
**Commit:** `ba3c408`
**Task terkait:** #10 NPC Monster Script (perapian struktur).

**Ringkasan menyeluruh:** Aer memindah folder modules Monster AI di Studio ke `ReplicatedStorage/Modules` dan rename jadi **EnemyController**; assistant "menjahit" penghubungnya agar sistem tetap jalan.

**Yang dikerjakan:**
- **Studio (langsung via MCP):** `MonsterController` — require path diubah dari `script.Parent:FindFirstChild("MonsterAI")` → `ReplicatedStorage.Modules:WaitForChild("EnemyController")`; header SETUP/ARSITEKTUR diupdate.
- **Lokal (source of truth, supaya Rojo tidak meng-overwrite):** file di-`git mv` ke `src/ServerScriptService/...` + `src/ReplicatedStorage/Modules/EnemyController/...`; `default.project.json` di-update (mapping `ServerScriptService` → `src/ServerScriptService`, `ReplicatedStorage/Modules` → `src/ReplicatedStorage/Modules`); edit path di file lokal `MonsterController.server.luau` agar match Studio.
- Modules internal pakai relative require (`script.Parent`) → tidak perlu diubah, aman dipindah.

**Verifikasi:** Studio — compile OK, 8/8 module `require` OK dari path baru, 0 referensi path lama, folder lama di SSS bersih. Lokal (ad-hoc `hermes-verify-*.py`, sudah dibersihkan) — 30 cek: mapping Rojo, path baru/hilang di MonsterController, structural balance, 8 modules ada, relative require aman → **ALL PASS**. **Belum playtest** (Aer yang tes).

**Catatan:** ReplicatedStorage ke-replicate ke client — source modules AI "terlihat" dari sisi player. Aman (logic tetap server-side), tapi jangan taruh sistem rahasia di sini.

---

### Entri #1 — Chasing mode Monster AI: implementasi + iterasi playtest
**Commit:** `5c400ad` → `63e6b67` → `f2fdb4f` (+ `be71b87` docs)
**Task terkait:** #10 NPC Monster Script.

**Ringkasan menyeluruh:** membangun fitur pilihan mode pengejaran monster, lalu memperbaikinya berdasarkan feedback playtest Aer.

#### 1. Chasing mode selectable (3 mode)
Dipilih per-monster via Attribute `ChaseMode` (String) di Model, fallback ke `Config.ChaseMode`:
- **PERSISTENT** — kunci 1 target sampai MATI/hilang; abaikan jarak & LOS; Safe Zone tetap dihormati. `PersistentGiveUpTime=0` = kejar selamanya.
- **NEAREST** (default) — kejar terdekat, retarget dinamis + anti-thrash.
- **ITEM_HOLDER** — prioritas pemegang Tool ber-Attribute `MonsterBait=true` (nama Tool bebas), fallback ke NEAREST bila tak ada holder.

**Anti-thrash 3 lapis** (cegah monster "di-main-mainin" 2 player oper-operan): commit time 2.5s + hysteresis 30%/8studs + interval 1s. Dipakai di NEAREST & ITEM_HOLDER, TIDAK di PERSISTENT.

**ITEM_HOLDER pakai Attribute `MonsterBait`** (bukan match nama Tool) — lebih fleksibel: banyak item beda bisa memicu monster cukup dengan tag Attribute.

#### 2. Fix berdasarkan feedback playtest ITEM_HOLDER
**Masalah yang dilaporkan Aer:**
- **Bug A** — 1 orang pegang MonsterBait, 1 tidak. Monster tetap ngejar yang **tidak** pegang walau pemegang bait muter-muter di dekat.
- **Bug B** — setelah membunuh player, monster **patroli dulu** (jeda lama) sebelum ngejar target berikutnya.

**Diagnosis:**
- **Bug A = A2 (bug logika, bukan salah setting).** Attribute monster sudah benar `ChaseMode=ITEM_HOLDER` (diverifikasi via MCP). Akar: `evaluateRetarget` memberlakukan hysteresis jarak ke SEMUA switch — termasuk pindah dari non-holder ke holder, jadi pemegang bait yang "tidak cukup lebih dekat" tak pernah diambil.
- **Bug B** — saat target mati, kode langsung `setState("PATROL")` + `task.wait(0.5)`; korban berikut baru ke-detect saat kebetulan masuk FOV sambil patroli.

**Solusi:**
- **Fix A2:** mode ITEM_HOLDER → **SWITCH INSTAN** ke pemegang bait saat target sekarang bukan holder (bypass commit time + hysteresis; item = prioritas mutlak). Dua holder → tetap hysteresis (anti-thrash).
- **Fix B:** helper `reacquireOrPatrol()` di CHASING & ATTACKING → begitu target invalid, langsung akuisisi ulang & lanjut CHASING kalau ada korban lain; `task.wait(0.5)` dibuang.
- **360° saat berburu:** `TargetFinder` dapat param `ignoreFOV`. Saat retarget & re-acquire pasca-kill, FOV dilewati (monster waspada penuh 360°). Akuisisi awal di IDLE/PATROL **tetap FOV** (realistis) — keputusan Aer.

#### 3. Parameter Config (di-tune sendiri oleh Aer)
`ChaseMode`, `BaitAttribute="MonsterBait"`, `PersistentGiveUpTime=0`, `RetargetCommitTime=2.5`, `RetargetInterval=1.0`, `RetargetHysteresis=0.30`, `RetargetMinGap=8`.

#### 4. File berubah
- `src/MonsterAI/Config.luau` — blok CHASE MODE & ANTI-THRASH, `BaitAttribute`.
- `src/MonsterAI/TargetFinder.luau` — `holdsTargetItem` (Attribute-based), `findItemHolder`, `acquireTarget`, param `ignoreFOV`.
- `src/MonsterController.server.luau` — context `chaseMode`+timing, `evaluateRetarget` (prioritas holder instan), `reacquireOrPatrol`, CHASING/ATTACKING rewrite.

#### 5. Verifikasi
Struktural balanced + Studio (3 script COMPILE_OK, source match, Attribute monster `ChaseMode=ITEM_HOLDER` terbaca) + behavioral test (chasing awal 8/8, fix retarget 5/5 — termasuk T1 bug report → SWITCH_HOLDER). **Belum playtest** (Aer yang tes).

---

## 📌 Cara pakai fitur Monster AI (referensi cepat)

1. **Pilih mode per-monster:** set Attribute `ChaseMode` (String) di Model monster → `PERSISTENT` / `NEAREST` / `ITEM_HOLDER`. Kosong = pakai default `Config.ChaseMode`.
2. **Tag item umpan (mode ITEM_HOLDER):** kasih Attribute `MonsterBait` (Bool, centang) di Tool umpan. Nama Tool bebas, bisa banyak item.
3. **Tune angka:** semua di `src/ReplicatedStorage/Modules/EnemyController/Config.luau` (blok CHASE MODE & ANTI-THRASH).
4. **Perilaku deteksi:** akuisisi awal (IDLE/PATROL) pakai FOV realistis; begitu sudah mengejar → deteksi 360°.

---

## 🐞 Catatan bug diketahui (harmless)

- **Bug #6** — `SafeZoneManager` mutasi return API. Belum diubah, tapi harmless (`GetTagged` return array baru + guard `table.find`).
