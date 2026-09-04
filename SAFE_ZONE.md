# Safe Zone — bilik toilet: sembunyi, napas terbatas, diusir

Pemain menekan **E** di depan bilik toilet → ia **masuk sembunyi**: karakternya pindah ke dalam,
kamera berubah jadi mengintip dari balik pintu (bisa lirik 120°), monster tidak bisa menarget **dan tidak bisa masuk**.
Pemain bisa **keluar kapan saja** dengan menekan **E / Space** lagi tanpa harus menunggu oksigen habis.
Jika tetap di dalam, napas cuma **20 detik** dengan efek guncangan kamera (camera shake) dan penglihatan mengabur (blur) saat mau habis. Habis napas → pemain **dikeluarkan paksa** dan bilik hangus 15 detik.

Bedanya dengan Safe Zone lama: dulu cukup berdiri di dalam Part untuk aman selamanya. Sekarang
bilik punya **state**, masuknya **disengaja**, dan "berada di dalam" tidak sama dengan "dilindungi".

---

## Cara Pakai

1. **View → Tag Editor**
2. Pilih Part bilik di Explorer (nama bebas)
3. Tempel tag **`SafeZone`**
4. Putar Part-nya supaya **muka depannya = arah pintu**
5. **Play**

Selesai. Tidak perlu menempel script, tidak perlu mengisi ID. ProximityPrompt dibuat otomatis.

Alternatif penanda: taruh Part di dalam `Folder` bernama **`SafeZones`** di `Workspace`. Folder
bersarang juga terbaca, jadi bilik boleh dikelompokkan per lantai / per ruangan.

Default satu bilik: **napas 20 detik, kapasitas 1 orang, hangus 15 detik**.

> **Arah pintu itu penting.** Titik sembunyi, titik intip, dan titik keluar semuanya dihitung dari
> `LookVector` Part (sumbu −Z lokal). Kalau pemain terlempar ke arah yang salah, putar Part-nya —
> jangan cari bug di script.

---

## Siklus Bilik

```
  READY ──(tekan E)──► OCCUPIED ──(napas habis)──► BREACHED
    ▲                      │                          │
    │                      │ (tekan E lagi)           │ pemain DIUSIR
    │                      ▼                          ▼
    └──(napas terisi)── READY                     COOLDOWN
                                                      │
                                                      └─► READY
```

| State | Arti | Monster | Prompt |
|---|---|---|---|
| `READY` | kosong, siap dipakai | boleh masuk | "Sembunyi" |
| `OCCUPIED` | ada yang sembunyi, napas berkurang | **ditahan di luar** | "Keluar" |
| `BREACHED` | napas habis — penghuni langsung diusir | boleh masuk | "Sembunyi" |
| `COOLDOWN` | hangus, menolak semua orang | boleh masuk | "Sembunyi" |

`BREACHED` itu **sekejap**: pada tick yang sama pemain dikeluarkan, dan karena bilik jadi kosong ia
langsung pindah ke `COOLDOWN`. Jangan heran kalau `SafeZoneState` nyaris tidak pernah terbaca
`BREACHED` dari luar — pakai `SafeZoneBreath` mendekati 0 sebagai penanda "mau kebobolan".

---

## Yang Terjadi Saat Sembunyi

| Aspek | Perlakuan |
|---|---|
| Posisi karakter | dipindah ke titik `hide` di tengah bilik, menghadap pintu |
| Gerakan | `WalkSpeed`/`JumpPower` = 0, `AutoRotate` off, `HumanoidRootPart` **Anchored** |
| Kamera | dipaku di titik `peek` (setinggi mata, dekat pintu), melihat keluar |
| Lirikan | terbatas **±45° horizontal, ±22° vertikal** — pemain terkurung, bukan bebas 360° |
| Transisi | fade hitam 0.35 detik saat masuk & keluar |
| Keluar | tekan **E** lagi, atau otomatis saat napas habis |

**Kenapa `Anchored`, bukan cuma `WalkSpeed = 0`:** monster raksasa yang menempel di pintu masih bisa
mendorong karakter keluar lewat celah kalau physics-nya aktif. Yang di-anchor hanya root, jadi
animasi tetap jalan.

**Fade itu pengganti sementara animasi.** Begitu ada aset animasi masuk-bilik dan animasi monster
menarik pemain keluar, kecilkan `Config.FadeTime` atau matikan.

---

## Attribute (opsional, ditempel pada Part bilik)

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `BreathTime` | Number | 20 | Lama perlindungan, detik |
| `MaxOccupants` | Number | 1 | Kapasitas; 1 = bilik toilet (rebutan) |
| `CooldownTime` | Number | 15 | Lama hangus setelah dipakai, detik |
| `TouchToEnter` | Bool | false | Masuk cukup berdiri di dalam — **tanpa** prompt/kamera/kunci |
| `BurnOnExit` | Bool | false | Keluar sebelum waktunya langsung menghanguskan bilik |
| `NoBarrier` | Bool | false | Bilik ini tidak menahan monster |
| `NoBreath` | Bool | false | Bilik aman **selamanya** — perilaku Safe Zone lama |

Contoh: lemari sempit yang cuma tahan sebentar → `BreathTime = 8`, `CooldownTime = 30`.
Ruang aman terbuka untuk 4 orang → `TouchToEnter = true`, `MaxOccupants = 4`, `NoBarrier = true`.

Nilai salah tipe atau negatif **diabaikan** (pakai default) dan dilaporkan `warn` sekali saat bilik
didaftarkan — supaya salah ketik tidak senyap.

---

## Titik Presisi (opsional)

Untuk mesh toilet yang pintunya tidak di tengah muka Part, taruh child di dalam Part bilik:

| Nama child | Mengatur |
|---|---|
| `HidePoint` | di mana karakter berdiri |
| `PeekPoint` | di mana kamera mengintip |
| `ExitPoint` | ke mana pemain dikeluarkan |

Boleh `Part` (pakai `CFrame`) atau `Attachment` (pakai `WorldCFrame`). Kalau ada, perhitungan
otomatis dilewati untuk titik itu.

> **Jebakan Attachment:** set `Parent` **dulu**, baru `WorldCFrame`. Attachment tanpa parent
> memperlakukan `WorldCFrame` sebagai CFrame lokal, jadi nilainya bergeser saat di-parent.

---

## Aturan yang Menutup Exploit

**Keluar-masuk tidak mereset napas.** Sisa napas dilanjutkan, bukan diisi ulang. Napas hanya penuh
lagi setelah bilik kosong selama `CooldownTime`. Terverifikasi: 6× siklus masuk-3-detik-keluar
menyisakan ~2 detik, bukan 20.

**Kapasitas dijaga sebelum karakter dipindah.** Pemain kedua di bilik `MaxOccupants = 1` tidak
dipindah, tidak dikunci, dan tidak mendapat perlindungan.

**Satu pemain tidak bisa menempati dua bilik** (`ALREADY_IN_ZONE`).

**Bilik yang `BREACHED`/`COOLDOWN` menolak semua orang** sampai masa hangusnya lewat.

---

## Dinding Monster

Selama bilik melindungi, ia jadi **solid khusus untuk monster**; pemain tetap bisa jalan
masuk-keluar. Ini pakai `CollisionGroup`, bukan `CanCollide` — `CanCollide = true` akan menahan
pemain juga.

| Grup | vs | Bertabrakan |
|---|---|---|
| `SafeZoneShield` | `MonsterBody` | ya — monster mentok |
| `SafeZoneShield` | `Default` | tidak — pemain lewat |
| `SafeZoneShield` | `SafeZoneShield` | tidak — bilik tidak saling dorong |

Badan monster otomatis masuk `MonsterBody` mengikuti tag `Monster`, jadi Enemy AI tidak perlu
diubah. Grup asli setiap Part **disimpan dan dipulihkan** kalau bilik di-untag.

Matikan per bilik dengan `NoBarrier = true`, atau global lewat `Config.BarrierEnabled = false`.

---

## Keluar dari Safe Zone

Pemain memiliki **dua cara** untuk keluar:
1. **Manual Kapan Saja (Tanpa Menunggu Oksigen Habis)**:
   - Tekan tombol **E** atau **Space** di keyboard.
   - Atau klik tombol/hint **`[E] LEAVE STALL`** di pojok layar.
   - Client langsung mengirim sinyal `LEAVE` ke server, pintu terbuka, kendali karakter pulih,
     dan pemain keluar secara mulus dengan transisi fade.
2. **Otomatis Saat Napas Habis (Breached)**:
   - Begitu timer 20 detik habis, bilik mengalami `BREACHED` dan pemain **dikeluarkan paksa** ke depan pintu.
   - Bilik masuk masa `COOLDOWN` (hangus) selama 15 detik.

---

## Efek Saat Oksigen Mau Habis (Suffocation Horror)

Bukan sekadar bar menyusut, sistem menghadirkan sensasi panik & asfiksia nyata di layar pemain:
- **Suffocation Camera Shake**: Saat napas < 35%, kepala pemain mulai bergetar tak beraturan karena sesak napas. Getaran semakin hebat dan liar saat napas mendekati 0.
- **Suffocation Blur (`Lighting.BlurEffect`)**: Penglihatan pemain mulai mengabur bertahap (blur naik hingga 16) seolah mau pingsan kekurangan oksigen di dalam bilik sempit.
- **Heartbeat Vignette Pulse**: Tepi layar diselimuti 4-sisi bayangan merah darah pekat yang berdenyut kencang mengikuti irama detak jantung saat panik.
- **Text Jitter**: Teks status `CAN'T HOLD ON!` bergetar panik di atas bar darah.

---

## UI Bar Napas — Silencio Carnival Horror

Bar muncul di bawah layar saat pemain sembunyi. Menggunakan tipografi horor badut (`Creepster` + `SpecialElite`),
vignette atmosferik di tepi layar yang berdenyut saat napas menipis, bar daging/karat dengan 20 goresan kuku,
dan proteksi anti-stuck (auto-hide jika menerima penolakan/cooldown).

Teks per keadaan:
- `HOLDING BREATH` (tenang)
- `LUNGS BURNING...` (napas di bawah 55%)
- `CAN'T HOLD ON!` (napas di bawah 25%, vignette merah darah berdenyut cepat)
- `IT HEARD YOU!` (kebobolan)
- `STALL IS COMPROMISED` (hangus / cooldown, auto-fade dalam 1.8 detik)

Kamera mengintip dibatasi **120 derajat total** (±60° kiri-kanan, ±25° atas-bawah) agar pemain merasa terkurung
di dalam toilet tanpa bisa memutar 360 derajat bebas. Mouse terkunci dengan `LockCenter` per frame agar
input lirikan responsif dan tidak terbentur CameraModule default.

**Modulnya bisa ditukar.** Kalau ada desain dari tim: ganti isi
`ReplicatedStorage/Modules/SafeZone/BreathBar`, atau taruh modul baru di folder itu dan ubah satu
konstanta `UI_MODULE` di `SafeZoneUI`. Server dan kamera tidak perlu disentuh.

Kontrak modul UI:

```lua
BreathBar.new()            -- membuat objek bar
bar:update(payload)        -- payload dari RemoteEvent "SafeZoneState"; nil = sembunyikan
bar:destroy()              -- lepas semua instance & koneksi
```

Tiga mockup HTML yang jadi dasar desain ini ada di `sketches/safezone-ui/` (yang dipakai: nomor 1,
*Napas Tercekik*).

Bentuk pesan dari server, dibedakan lewat `kind`:

| `kind` | Isi | Tujuan |
|---|---|---|
| `STATE` | `state, breath, max, fraction, count, capacity, eternal` | bar napas |
| `ENTER` | `zone, peekCF, doorDir, fade, yawLimit, pitchLimit` | pasang kamera intip |
| `EXIT` | `fade, forced` | lepas kamera (`forced` = diusir, bukan keluar sendiri) |

`state = "NONE"` berarti pemain sedang tidak di bilik mana pun. Pesan tanpa `kind` diperlakukan
sebagai `STATE` supaya modul UI lama tetap jalan.

---

## Kanal untuk Efek Tim (suara, lampu, partikel)

Setiap bilik menerbitkan keadaannya sebagai **Attribute pada Part-nya sendiri**:

| Attribute | Isi |
|---|---|
| `SafeZoneState` | `READY` / `OCCUPIED` / `BREACHED` / `COOLDOWN` |
| `SafeZoneBreath` | Sisa napas, detik (1 desimal) |

Efek bisa dipasang tanpa menyentuh script sistem — pola yang sama dengan `AIState` milik Enemy AI:

```lua
-- contoh script tim, ditempel di mana saja
local bilik = workspace.ToiletBilik1
bilik:GetAttributeChangedSignal("SafeZoneState"):Connect(function()
    if bilik:GetAttribute("SafeZoneState") == "COOLDOWN" then
        -- putar suara pintu didobrak / engsel rusak
    end
end)
```

---

## Struktur Kode

```
src/
├── ServerScriptService/
│   └── SafeZoneController.server.luau     ← orchestrator (Script server)
├── ReplicatedStorage/Modules/SafeZone/
│   ├── Config.luau        ← semua angka, nama tag, teks prompt
│   ├── Geometry.luau      ← OBB check, cari bilik, cari root karakter
│   ├── Settings.luau      ← resolver Attribute per bilik + validasi
│   ├── Anchors.luau       ← titik hide / peek / exit dari geometri Part
│   ├── Occupancy.luau     ← pindah & kunci karakter, pulihkan saat keluar
│   ├── PromptManager.luau ← ProximityPrompt per bilik, teks Sembunyi/Keluar
│   ├── Barrier.luau       ← CollisionGroup: dinding khusus monster
│   ├── Zone.luau          ← satu bilik: napas, penghuni, cooldown
│   ├── ZoneService.luau   ← state pusat, detak, pengusiran, siaran client
│   ├── BreathBar.luau     ← UI bar napas (bisa ditukar)
│   └── PeekCamera.luau    ← kamera mengintip + fade (client)
└── StarterPlayer/StarterPlayerScripts/
    └── SafeZoneUI.client.luau              ← penghubung Remote → UI & kamera
```

**Sambungan ke Enemy AI:** `EnemyController/SafeZoneManager` jadi jembatan — ia menanyakan
`ZoneService:isProtected()`. Nama fungsinya tetap `isInSafeZone`, jadi `TargetFinder` dan
`EnemyController` tidak diubah sama sekali.

**Kalau folder `SafeZone` tidak ada** di place, `SafeZoneManager` jatuh ke perilaku lama (deteksi
geometris murni, tanpa timer). Menghapus sistem bilik tidak mematikan Enemy AI.

---

## Jebakan

- **Edit mode: bilik terlihat tembus dan prompt tidak muncul.** Script server tidak jalan di edit
  mode. Ini normal, bukan tag yang gagal.
- **Arah pintu = muka depan Part.** Salah putar → pemain terlempar ke dalam dinding.
- **Bilik ber-napas hanya melindungi player.** Karakter NPC (teman, dummy) butuh `NoBreath = true`
  — timer napas perlu identitas pemain dan UI.
- **Perubahan ModuleScript tidak berlaku di sesi Play yang sudah jalan** (`require` di-cache).
  Stop lalu Play ulang.
- **`MaxOccupants = 0`** dibulatkan ke 1 + `warn`; bilik berkapasitas nol tidak ada gunanya.
- **Jangan panggil `ZoneService:reset()` / `_debugSetOccupant()` saat runtime** — keduanya khusus
  uji perilaku.
