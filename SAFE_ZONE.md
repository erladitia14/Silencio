# Safe Zone — bilik aman berbatas napas

Area aman yang **tidak permanen**. Pemain masuk bilik (toilet, lemari, ruang kecil), monster tidak
bisa menarget **dan tidak bisa masuk**. Tapi napasnya terbatas: begitu habis, dinding terbuka dan
monster boleh masuk. Setelah dipakai, bilik hangus sebentar sebelum bisa dipakai lagi.

Bedanya dengan Safe Zone lama: dulu cukup berdiri di dalam Part untuk aman selamanya, jadi pemain
bisa nongkrong di sana sampai bosan. Sekarang bilik punya **state**, dan "berada di dalam" tidak
sama dengan "dilindungi".

---

## Cara Pakai

1. **View → Tag Editor**
2. Pilih Part bilik di Explorer (nama bebas)
3. Tempel tag **`SafeZone`**
4. **Play**

Selesai. Tidak perlu menempel script, tidak perlu mengisi ID.

Alternatif: taruh Part di dalam `Folder` bernama **`SafeZones`** di `Workspace`. Folder bersarang
juga terbaca, jadi bilik boleh dikelompokkan per lantai / per ruangan.

Default satu bilik: **napas 20 detik, kapasitas 1 orang, hangus 15 detik**.

---

## Siklus Bilik

```
  READY ──(ada yang masuk)──► OCCUPIED ──(napas habis)──► BREACHED
    ▲                             │                          │
    │                             │ (keluar)                 │ (keluar)
    │                             ▼                          ▼
    └────(napas terisi penuh)── READY                    COOLDOWN
                                                             │
                                                             └─► READY
```

| State | Arti | Monster |
|---|---|---|
| `READY` | kosong, siap dipakai | boleh masuk |
| `OCCUPIED` | ada yang dilindungi, napas berkurang | **ditahan di luar** |
| `BREACHED` | napas habis, perlindungan lepas | **boleh masuk** |
| `COOLDOWN` | hangus, belum bisa dipakai | boleh masuk |

---

## Attribute (opsional, ditempel pada Part bilik)

Isi hanya kalau bilik ini mau **beda** dari default. Nama Attribute = nama setelan, jadi tidak ada
yang perlu dihafal.

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `BreathTime` | Number | 20 | Lama perlindungan, detik |
| `MaxOccupants` | Number | 1 | Kapasitas; 1 = bilik toilet (rebutan) |
| `CooldownTime` | Number | 15 | Lama hangus setelah dipakai, detik |
| `BurnOnExit` | Bool | false | Keluar sebelum waktunya langsung menghanguskan bilik |
| `NoBarrier` | Bool | false | Bilik ini tidak menahan monster (cuma melindungi target) |
| `NoBreath` | Bool | false | Bilik aman **selamanya** — perilaku Safe Zone lama |

Contoh: lemari sempit yang cuma tahan sebentar → `BreathTime = 8`, `CooldownTime = 30`.
Ruang aman besar untuk 4 orang → `MaxOccupants = 4`, `NoBarrier = true`.

Nilai salah tipe atau negatif **diabaikan** (pakai default) dan dilaporkan `warn` sekali saat bilik
didaftarkan — supaya salah ketik tidak senyap.

---

## Aturan yang Menutup Exploit

**Keluar-masuk tidak mereset napas.** Sisa napas dilanjutkan, bukan diisi ulang. Napas hanya penuh
lagi setelah bilik kosong selama `CooldownTime`. Tanpa aturan ini, pemain bisa keluar-masuk terus
untuk aman selamanya.

**Kapasitas dijaga saat masuk, bukan sesudahnya.** Pemain kedua di bilik `MaxOccupants = 1` tidak
mendapat perlindungan sama sekali — dia berdiri di sana tapi tetap bisa ditarget.

**Bilik yang sudah `BREACHED` tidak melindungi siapa pun** sampai kosong dan lewat masa hangus.

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
diubah. Grup asli setiap Part **disimpan dan dipulihkan** kalau bilik di-untag — script ini tidak
menimpa setelan tim secara permanen.

Matikan per bilik dengan `NoBarrier = true`, atau global lewat `Config.BarrierEnabled = false`.

---

## UI Bar Napas

Bar muncul di bawah layar saat pemain berada di bilik: sisa detik + warna yang berubah
(hijau → kuning → merah) sesuai sisa napas.

**Modulnya bisa ditukar.** UI sekarang buatan sendiri, sementara. Kalau ada desain dari tim:
ganti isi `ReplicatedStorage/Modules/SafeZone/BreathBar`, atau taruh modul baru di folder itu dan
ubah satu konstanta `UI_MODULE` di `SafeZoneUI`. Server tidak perlu disentuh.

Kontrak modul UI:

```lua
BreathBar.new()            -- membuat objek bar
bar:update(payload)        -- payload dari RemoteEvent "SafeZoneState"
bar:destroy()              -- lepas semua instance & koneksi
```

Bentuk `payload`: `{ state, breath, max, fraction, count, capacity, eternal }`.
`state = "NONE"` berarti pemain sedang tidak di bilik mana pun.

---

## Kanal untuk Efek Tim (suara, lampu, partikel)

Setiap bilik menerbitkan keadaannya sebagai **Attribute pada Part-nya sendiri**:

| Attribute | Isi |
|---|---|
| `SafeZoneState` | `READY` / `OCCUPIED` / `BREACHED` / `COOLDOWN` |
| `SafeZoneBreath` | Sisa napas, detik (1 desimal) |

Jadi efek bisa dipasang tanpa menyentuh script sistem — pola yang sama dengan `AIState` milik
Enemy AI:

```lua
-- contoh script tim, ditempel di mana saja
local bilik = workspace.ToiletBilik1
bilik:GetAttributeChangedSignal("SafeZoneState"):Connect(function()
    if bilik:GetAttribute("SafeZoneState") == "BREACHED" then
        -- putar suara pintu didobrak
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
│   ├── Config.luau        ← semua angka & nama tag
│   ├── Geometry.luau      ← OBB check, cari bilik, cari root karakter
│   ├── Settings.luau      ← resolver Attribute per bilik + validasi
│   ├── Barrier.luau       ← CollisionGroup: dinding khusus monster
│   ├── Zone.luau          ← satu bilik: napas, penghuni, cooldown
│   ├── ZoneService.luau   ← state pusat + detak + siaran ke client
│   └── BreathBar.luau     ← UI bar napas (bisa ditukar)
└── StarterPlayer/StarterPlayerScripts/
    └── SafeZoneUI.client.luau              ← penghubung Remote → modul UI
```

**Sambungan ke Enemy AI:** `EnemyController/SafeZoneManager` yang dulu menghitung geometri sendiri
sekarang jadi jembatan — ia menanyakan `ZoneService:isProtected()`. Nama fungsinya tetap
`isInSafeZone`, jadi `TargetFinder` dan `EnemyController` tidak diubah sama sekali.

**Kalau folder `SafeZone` tidak ada** di place, `SafeZoneManager` jatuh ke perilaku lama (deteksi
geometris murni, tanpa timer). Menghapus sistem bilik tidak mematikan Enemy AI.

---

## Jebakan

- **Edit mode: bilik terlihat tembus.** Script server tidak jalan di edit mode, jadi dinding baru
  aktif saat Play. Ini normal, bukan tag yang gagal.
- **Bilik ber-napas hanya melindungi player.** Karakter NPC (teman, dummy) butuh `NoBreath = true`
  — timer napas perlu identitas pemain dan UI.
- **Perubahan ModuleScript tidak berlaku di sesi Play yang sudah jalan** (`require` di-cache).
  Stop lalu Play ulang.
- **`MaxOccupants = 0`** dibulatkan ke 1 + `warn`; bilik berkapasitas nol tidak ada gunanya.
