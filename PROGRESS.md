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

### Entri #5 — Audit sistem animasi skin (tanpa perubahan kode)
**Task terkait:** #10 NPC Monster Script.

**Konteks:** Aer menanyakan apakah animasi badut masih di-handle script `Clown.Anim`, dan apakah cukup me-*rename* Animation yang sudah ada untuk memakai beberapa animasi. Turn ini **murni investigasi + uji** — tidak ada kode yang diubah.

**Keadaan sebenarnya di Studio (dibaca, bukan diasumsikan):**

| Instance | Kelas | Status | Catatan |
|---|---|---|---|
| `Clown.Anim` | Script | **Enabled = false** | Sudah dimatikan `SkinBinder` (aturan satu penyetir). Isinya 1 Animation `103353830011402` — ID **R15 default**, bukan animasi khas badut |
| `Hitbox.Animate` | **LocalScript** | Enabled = true | Paket R15 bawaan, 27 animasi standar Roblox |
| `Clown.AnimationController` | AnimationController | aktif | Disetir `SkinAnimator` mengikuti `AIState` |
| `Hitbox.Humanoid.Animator` | Animator | aktif | Jalur `AnimationManager` |

Dua koreksi terhadap asumsi yang beredar:
1. **Animasi TIDAK lagi di-handle script Clown** — `Anim` sudah disabled sejak `SkinBinder` dipasang.
2. **`Hitbox.Animate` itu LocalScript**, dan LocalScript tidak berjalan di NPC non-player. Jadi 27 animasi di dalamnya sebetulnya tidak dieksekusi siapa pun; yang benar-benar menyetir adalah `AnimationManager` / `SkinAnimator`.

**Hasil uji `SkinAnimator` (18/18 di Studio, modul dimuat segar):**
- Folder `Animations` lengkap → 5 state dapat track **berbeda** (bukan berbagi), sumber tercatat `Animations/<Nama>`.
- `applyState` benar: `IDLE`→Idle, `PATROL`→Walk, `CHASING`→Run, `DEAD`→Death. `Attack` via `playOnce` (Looped=false) sementara Idle tetap Looped.
- Nama huruf kecil (`animations/idle`) tetap kebaca.
- Isi sebagian (cuma Idle+Run) → sisanya fallback, tidak error.
- **Kondisi NPC sekarang direplikasi:** tanpa folder `Animations`, kelima state **berbagi satu track** → itu sebabnya idle/jalan/ngejar terlihat sama.
- **Jebakan terkonfirmasi:** Animation yang di-*rename* jadi `Idle` tapi berada **di dalam script `Anim`** (bukan di folder `Animations`) tetap terbaca sebagai `fallback-tunggal`. Rename saja tidak cukup — folder wajib ada.

**Kesimpulan untuk Aer:** modul sudah siap, tidak perlu ubah script. Yang dibutuhkan: buat folder `Animations` di dalam **skin** (`Clown`), isi Animation `Idle`/`Walk`/`Run`/`Attack`/`Death` beserta AnimationId.

**Peringatan aset (belum terverifikasi, di luar jangkauan MCP):** badut ini skinned mesh bertulang `mixamorig:*` yang diputar via `AnimationController`. Animasi **R15 Roblox tidak akan cocok** dengan skeleton itu. Animasi Mixamo harus di-publish ulang terhadap rig badut, dan di-upload oleh akun/grup yang sama dengan tempat game berjalan — kalau tidak, `LoadAnimation` gagal saat runtime. Kecocokan ID hanya terbukti lewat Play.

---

### Entri #4 — Spesifikasi per-NPC lewat Attribute (override Config)
**Task terkait:** #10 NPC Monster Script.

**Ringkasan:** Aer minta tiap NPC bisa punya spesifikasi berbeda (speed, damage, jarak deteksi) **tanpa mengubah script**. Sebelumnya `Config` itu satu tabel global — semua NPC pakai angka yang sama. Sekarang 8 knob bisa di-override per-NPC lewat Attribute di Properties Model, memakai pola yang sudah dipakai `ChaseMode`: **Attribute NPC menang, kalau kosong pakai default global.**

**Yang dibangun:**
- `Config.get(model, key)` — resolver: baca Attribute NPC dulu, fallback ke default. Silent, karena dipanggil tiap tick.
- `Config.validateOverrides(model)` — dipanggil **sekali** saat init; melaporkan `warn` kalau Attribute salah tipe / negatif. Tanpa ini, salah ketik akan diam-diam diabaikan dan tim bingung kenapa "tidak ngefek".
- Whitelist 8 knob (lihat tabel di bawah). Knob lain (`RetargetMinGap`, `PathTimeout`, `AgentRadius`, …) sengaja **tidak** bisa dioverride — itu tuning sistem, bukan spesifikasi karakter.
- 12 titik pemakaian diganti ke resolver: `TargetFinder` (3× DetectionRadius, LoseTargetRadius, FieldOfView), `CombatManager` (Damage, AttackCooldown), `EnemyController` (4× PatrolSpeed, ChaseSpeed, PatrolWaitTime), `AnimationManager` (ambang walk→run).

**Bug ikutan yang ketemu:** `AnimationManager` menentukan ambang walk→run dari `Config.PatrolSpeed` **global**. Kalau sebuah NPC di-override `PatrolSpeed = 20`, animasinya akan memutar "Run" padahal itu kecepatan patroli normalnya. Sekarang ambangnya relatif terhadap PatrolSpeed NPC itu sendiri.

**Keputusan desain:** `0` dianggap nilai **sah** (mis. `Damage = 0` untuk monster yang cuma menakuti, `PatrolWaitTime = 0` untuk patroli tanpa henti). Yang ditolak hanya negatif dan salah tipe. Kalau `0` diperlakukan sebagai "kosong", knob-knob itu jadi tidak bisa dinolkan.

**Tidak dikerjakan (atas keputusan Aer):** plugin Studio auto-fill Attribute. Konsekuensinya jujur: Attribute **tidak muncul sendiri** di Properties — tim harus menambahkannya manual (tabel referensi di bawah jadi rujukan nama). Ditolak karena menambah beban install plugin per anggota tim untuk kenyamanan kosmetik.

**Verifikasi:** compile 11/11 di Studio; perilaku 19/19 (default, override, isolasi antar-NPC, batas `0`, tolak negatif/String/Bool, desimal, knob non-overridable tetap global, integrasi `CombatManager` termasuk damage nyata 100→60 dengan `Damage=40`); FOV & chase-range 13/13; statis+parity 54/54 dengan 3 kontrol negatif exit 1.

**Koreksi diriku sendiri saat menguji:** satu FAIL awal ternyata **asersi tesku yang salah**, bukan bug — aku menaruh titik "depan" di `+Z` padahal `LookVector` root menghadap `−Z`, jadi titik itu justru 180° di belakang. Setelah titik uji dihitung dari `LookVector`, 13/13 lulus. Ini kekeliruan yang sama polanya dengan kasus auto-align: jangan berasumsi soal arah, hitung dari data.

**Belum playtest:** perilaku override saat game jalan (monster dengan `ChaseSpeed` tinggi benar-benar lebih cepat, dst). Playtest = Aer.

---

### Entri #3 — Animasi otomatis, pola "driver + skin", jangkauan serang adaptif
**Commit:** `e3f4b2c` → `2182678` (auto-align, lihat #4b)
**Task terkait:** #10 NPC Monster Script.

**Ringkasan menyeluruh:** Aer minta script AI dibuat **se-versatile mungkin** — tim bisa memakainya tanpa mengubah isinya, dan dia tidak mau mengurus animasi per-NPC. Sesi ini memindahkan animasi keluar dari core AI, lalu membangun sistem NPC visual berbasis dua tag. Empat bug nyata ketemu di jalan, semuanya dari playtest Aer.

#### 1. Animasi keluar dari core AI
EnemyController tidak lagi memaksakan animasi; ia hanya **melapor**:
- Attribute `AIState` → `IDLE` | `PATROL` | `CHASING` | `ATTACKING` | `DEAD` (di-set tiap `onEnter`)
- BindableEvent `AISignal` (otomatis dibuat di Model) → `Attack`, `TargetAcquired`, `TargetLost`, `Died`

Kejadian sekejap pakai **event**, bukan attribute: set nilai yang sama tidak memicu sinyal, jadi serangan ke-2 akan senyap. `CombatManager` berhenti menyentuh Animator sama sekali.

#### 2. AnimationManager: otomatis, cukup tag
Baca ID animasi dari dalam Model sendiri — folder `Animations` → paket `Animate` milik rig → default Roblox. Nama **tidak case-sensitive**.

**Bug ditemukan:** pencarian dulu case-sensitive (`Idle`), padahal rig Roblox menamai anaknya huruf kecil (`idle`). Akibatnya **semua** animasi asli NPC diabaikan diam-diam dan sistem selalu jatuh ke ID hardcode. Setelah fix: Clown 5/5 animasi terbaca dari `Animate/` miliknya.

Opt-out: Attribute `NoAutoAnimations`.

#### 3. Pola "driver + skin" — dua tag, nol konfigurasi (ide Aer)
NPC bisa terdiri dari **dua model di folder yang sama**:
```
Clown (Folder)
├── Hitbox  <- tag "Monster"      : rig R15 + Humanoid. Gerak, damage, tabrakan.
└── Clown   <- tag "MonsterSkin"  : mesh visual (import Mixamo) + animasi.
```
Perlu karena karakter import (bone `mixamorig:*`, satu MeshPart, `AnimationController`) tidak punya Humanoid → tidak bisa chase/patrol/damage/pathfinding. Rig jadi "mesin", mesh jadi kulit. **Tanpa retargeting.**

**`SkinBinder.luau`** (modul baru) otomatis mengerjakan: weld tiap part skin → `HumanoidRootPart`; skin `CanCollide=false` + `Massless=true`; luruskan orientasi; sembunyikan rig; matikan script animasi lama yang berebut Animator; pasang animator.

**`SkinAnimator.luau`** (modul baru) memutar animasi skin lewat `AnimationController`-nya sendiri, mengikuti `AIState`. Satu `AnimationId` = satu track (state yang memakai ID sama berbagi track, jadi pindah state tidak menghentikan-memulai animasi yang sama).

Opt-out / tuning: `KeepRigVisible`, `KeepSkinCollision`, `KeepSkinOrientation`, `SkinYawOffset` (koreksi arah hadap skin, derajat).

#### 4. Empat bug dari playtest Aer

| Gejala | Akar masalah |
|---|---|
| NPC **diam total** | `MaxHealth`/`Health` = 0 → main loop `while Health > 0` tidak pernah jalan sekali pun. Sekarang ada guard + `warn`. |
| Monster besar **tak bisa deal damage** | `AttackRadius` diukur pusat-ke-pusat. `Hitbox` tinggi 12 studs: jarak saat player menempel 6.56 > radius 4. Jangkauan sekarang dihitung dari ukuran NPC (Hitbox → 7.55, NPC kecil tetap 4.00). Override: Attribute `AttackRadius`. |
| Monster **buta permanen** | Raycast LOS hanya memfilter rig, padahal skin adalah **sibling di luar model** → ray menabrak badan sendiri dari <1 stud, LOS selalu gagal. `CanCollide=false` tidak menolong. `SkinBinder:getIgnoreList()` sekarang memfilter rig + skin. |
| Badut **jalan menyamping** | `WeldConstraint` membekukan offset saat dibuat; mesh import melenceng 90°. Orientasi mesh sekarang diluruskan ke rig **sebelum** weld (posisi tidak digeser). Perjalanan menuju solusi yang benar butuh beberapa iterasi — lihat #4b. |

#### 4b. Auto-align: perjalanan sampai benar (acuan MESH, bukan bone)
**Commit final: `2182678`.** Aer memutar `HitBox`, mesh ikut, animasi tetap menyimpang. Permintaannya jelas: **harus otomatis, jangan align manual.** Butuh beberapa kali salah:

1. **Percobaan 1 — acuan MeshPart.** Mesh lurus, tapi Aer lapor "arah animasinya salah" saat jalan → kusimpulkan (keliru) bahwa acuan yang benar adalah bone.
2. **Percobaan 2 — acuan bone (`58c05df`).** Kupindah acuan ke skeleton (`Bone`). Sepanjang jalan menemukan dua gotcha nyata: `Bone.CFrame` itu **relatif parent** (yang di ruang dunia `WorldCFrame`), dan align **tidak berefek** kalau weld belum dibongkar (weld menarik mesh balik). Kedua hal itu benar dan tetap relevan. Tapi hasilnya: badut malah nyamping saat jalan.
3. **Percobaan 3 — balik ke MESH + knob (`2182678`, final).** Ternyata **premisku soal bone salah**. Saat NPC jalan, yang memutar badan ke arah gerak adalah root rig; mesh mengikutinya lewat weld. Animasi walk cuma menggerakkan kaki di tempat — **tidak** mengubah arah hadap badan. Jadi arah badan saat jalan = **arah MeshPart**, bukan bone.

**Solusi final:**
- Acuan align = geometri MeshPart (`findPivot` → MeshPart / PrimaryPart / BasePart pertama).
- `targetRotation(rig, root)` = orientasi rig + **`SkinYawOffset`** (Attribute derajat, default 0). Untuk aset yang "depan"-nya tidak sejajar sumbu Roblox (mesh Mixamo sering kebalik 180° atau nyamping 90°), tim cukup ketik satu angka — tanpa mengubah script inti.
- Urutan tetap: `needsAlign()` → bongkar weld (`removeSkinWelds`) → putar → weld ulang.

**Pelajaran proses:** aku dua kali menyimpulkan dari pose diam di edit mode ("kelihatan lurus/miring") padahal arah saat **jalan** hanya terbukti lewat Play. Arah animasi berjalan tidak bisa diverifikasi dari geometri statis — itu domain playtest, bukan MCP.

Verifikasi final (`2182678`): sandbox 9/9 (mesh menyimpang 90°/120° → lurus; `SkinYawOffset` 180° → 180° dari rig, 90° → 90°; idempoten; `KeepSkinOrientation` dihormati; rig arah bebas ikut); aset asli mesh 90° → **0.00°** dari rig, posisi tidak melompat, 1 weld; statis+parity 26/26; kontrol negatif exit 1.

**Masih belum terverifikasi:** apakah 0° itu arah depan yang benar saat badut **jalan**. Kalau ternyata mundur/nyamping, cukup set `SkinYawOffset` — bukan perubahan kode. Playtest = Aer.

#### 5. Rig hanya disembunyikan saat Play
`Transparency = 1` cuma diterapkan bila `RunService:IsRunning()`. Kalau dilakukan di edit mode, nilainya **ikut tersimpan ke file place** dan rig hilang permanen dari viewport — padahal di edit mode rig perlu terlihat untuk diposisikan/di-skala.

#### 6. File berubah
Baru: `SkinBinder.luau`, `SkinAnimator.luau`, `ServerStorage/NPCAnimationTemplate.server.luau` (contoh untuk tim).
Diubah: `EnemyController.server.luau`, `TargetFinder.luau`, `AnimationManager.luau`, `CombatManager.luau`.

#### 7. Verifikasi
Ad-hoc (proyek ini tidak punya test runner / build step / linter Luau — tidak ada perintah kanonik): compile via `loadstring` di Studio (10/10 script), uji perilaku per fitur di Studio, parity byte lokal↔Studio, plus kontrol negatif tiap batch (mutan sengaja dirusak → exit 1). Pra-push: **31/31 pass**, 7 file byte-identical dengan Studio. Script verifikasi dibuat di `Temp` lalu dihapus.

**Belum playtest** untuk kondisi akhir (rig hilang + mesh tampil saat Play, monster mengejar & memukul). Playtest = Aer.

**Catatan proses:** dua kali aku bertindak dari data statis tanpa bukti runtime (`CanCollide`, lalu `HipHeight`) dan dua-duanya salah sampai Aer harus reset project. Pelajarannya: physics mati di edit mode, jadi dugaan soal gerakan/tabrakan **harus** dikonfirmasi playtest sebelum diperlakukan sebagai fakta. Juga: perubahan ModuleScript tidak berlaku pada sesi Play yang sudah jalan (`require` di-cache) — harus Stop lalu Play ulang.

**Gotcha alat verifikasi** (bikin FAIL palsu, jangan diulang):
- `loadstring` membuat **salinan modul terpisah**, jadi state antar-modul (mis. `boundSkins`) tidak terbagi. Untuk uji lintas modul, pakai `require()` atau shim `require` yang mengembalikan instance yang sama.
- Skrip cek statis yang membuang komentar juga **mengosongkan string literal** — assert soal isi string (`"SkinWeld"`, `IsA("Bone")`) harus memakai source mentah.
- Luau punya **if-expression** (`return if x then a else b`) yang tidak ditutup `end`, jadi hitung-blok naif melaporkan selisih palsu. Kebenaran sintaksis ditentukan `loadstring` di Studio.

---

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

## 📌 NPC baru: cukup tag (referensi cepat)

**NPC biasa (rig R15 ber-Humanoid):** kasih tag `Monster` → dapat AI + animasi otomatis. Selesai.

**NPC pakai mesh visual terpisah** (mis. import Mixamo yang tak punya Humanoid) — dua model di **folder yang sama**:

| Instance | Tag | Perannya |
|---|---|---|
| rig R15 + Humanoid | `Monster` | gerak, damage, tabrakan, tinggi berdiri |
| mesh visual | `MonsterSkin` | tampilan + animasi |

Sistem otomatis: weld ke `HumanoidRootPart`, matikan collision skin, luruskan orientasi, sembunyikan rig **saat Play**, matikan script animasi lama yang bentrok, sambungkan animasi ke `AIState`.

**Boleh diputar bebas.** Kalau kamu memutar rig di Explorer, sistem meluruskan arah skin otomatis saat bind — acuannya **orientasi MeshPart**, jadi badan menghadap arah jalan. Tidak perlu align manual. Kalau "depan" mesh ternyata kebalik (aset Mixamo), set Attribute `SkinYawOffset` (derajat) di rig, sekali saja.

**Animasi per-state (opsional):** taruh `Animation` di dalam **folder bernama `Animations`**, dengan nama `Idle` / `Walk` / `Run` / `Attack` / `Death`. Nama folder & animasi **tidak case-sensitive** (`animations/idle` juga kebaca). Kalau cuma ada satu animasi, dipakai untuk semua state.

Peta state → animasi: `IDLE`→`Idle`, `PATROL`→`Walk`, `CHASING`→`Run`, event `Attack`→`Attack` (sekali, tidak loop), event `Died`→`Death`.

**Letak folder menentukan siapa yang memutar:**

| NPC | Folder `Animations` ditaruh di | Diputar oleh |
|---|---|---|
| Satu Model biasa (rig ber-Humanoid) | Model itu sendiri | `AnimationManager` (via Humanoid) |
| Pola driver+skin | **Model skin** (yang ber-tag `MonsterSkin`) | `SkinAnimator` (via AnimationController) |

Contoh untuk badut (`Clown` = skin, `Hitbox` = rig):

```
workspace.Clown
├── Hitbox          <- tag "Monster"      (rig; folder animasi TIDAK di sini)
└── Clown           <- tag "MonsterSkin"
    └── Animations  <- folder di SKIN
        ├── Idle    (Animation -> isi AnimationId)
        ├── Walk
        ├── Run
        ├── Attack
        └── Death
```

**Jebakan (sudah diuji):** me-*rename* `Animation` yang sudah ada — misalnya yang nempel di dalam script `Anim` — menjadi `Idle` **tidak cukup**. Resolver mencari folder `Animations` sebagai anak dari Model; Animation di luar folder itu hanya kepungut sebagai *fallback tunggal*, jadi semua state tetap memakai animasi yang sama. Folder-nya wajib ada.

Isi sebagian saja juga boleh: nama yang tidak ada jatuh ke fallback, tidak error.

**Tim mau animasi berlogika sendiri:** `NoAutoAnimations` = true, lalu ikuti Attribute `AIState` + BindableEvent `AISignal` (`Attack`, `TargetAcquired`, `TargetLost`, `Died`). Contoh siap pakai: `ServerStorage/NPCAnimationTemplate`. **Jangan ubah EnemyController.**

**Attribute yang tersedia**

| Attribute | Tipe | Fungsi |
|---|---|---|
| `ChaseMode` | String | `PERSISTENT` / `NEAREST` / `ITEM_HOLDER` |
| `AttackRadius` | number | kunci jangkauan serang (default: dihitung dari ukuran NPC) |
| `NoAutoAnimations` | Bool | animasi diurus script NPC sendiri |
| `KeepRigVisible` | Bool | rig tetap tampak saat Play |
| `KeepSkinCollision` | Bool | jangan matikan collision skin |
| `KeepSkinOrientation` | Bool | jangan luruskan orientasi skin |
| `SkinYawOffset` | number | koreksi arah hadap skin, derajat (mis. 180 kalau mesh menghadap mundur, 90 kalau nyamping). Default 0 |

### Spesifikasi per-NPC (semua Number, opsional)

Isi hanya kalau NPC ini mau **beda** dari default. Nama Attribute = nama field Config, jadi tidak perlu hafal apa-apa. Tidak diisi → pakai default global.

| Attribute | Default | Fungsi |
|---|---|---|
| `PatrolSpeed` | 10 | WalkSpeed saat patroli / idle |
| `ChaseSpeed` | 18 | WalkSpeed saat mengejar |
| `DetectionRadius` | 45 | Jarak maksimum melihat player (studs) |
| `LoseTargetRadius` | 58 | Jarak target dianggap lepas (studs) |
| `FieldOfView` | 160 | Sudut pandang (derajat); 360 = waspada segala arah |
| `AttackCooldown` | 1.5 | Jeda antar serangan (detik) |
| `Damage` | 25 | Damage per serangan; 0 = tidak melukai |
| `PatrolWaitTime` | 2 | Lama diam di waypoint (detik) |

Contoh monster bos: `ChaseSpeed = 26`, `Damage = 40`, `DetectionRadius = 80`. NPC lain **tidak terpengaruh**.

Aturan nilai: Number **≥ 0**. `0` sah (mis. `Damage = 0` untuk monster jinak). Negatif atau salah tipe (String/Bool) **diabaikan** → pakai default, dan dilaporkan `warn` sekali saat NPC init supaya salah ketik tidak senyap.

Di luar daftar ini nilainya tetap global (`RetargetMinGap`, `PathTimeout`, `AgentRadius`, dst) — diubah di `Config.luau` kalau perlu. `AttackRadius` beda jalur: sudah adaptif dari ukuran NPC, Attribute-nya mengunci hasil hitungan itu.

**Jebakan yang sudah kena sekali** (cek ini dulu kalau NPC aneh):
- `MaxHealth`/`Health` = 0 → NPC **diam total tanpa error**. Sudah ada guard + `warn`.
- Monster raksasa tak bisa memukul → jangkauan sekarang otomatis proporsional.
- Perubahan ModuleScript **tidak berlaku** pada sesi Play yang sudah jalan (`require` di-cache) → Stop lalu Play ulang.

---

## 🐞 Catatan bug diketahui (harmless)

- **Bug #6** — `SafeZoneManager` mutasi return API. Belum diubah, tapi harmless (`GetTagged` return array baru + guard `table.find`).
