--[[
	Config.luau  (SafeZone)
	-----------------------
	Konfigurasi terpusat sistem Safe Zone "bilik toilet".

	KONSEP:
	  Pemain menekan ProximityPrompt di bilik -> ia SEMBUNYI di dalam:
	  karakternya dipindah ke dalam bilik, gerakannya dikunci, kamera
	  berubah jadi "mengintip" ke luar. Monster tidak bisa menarget dan
	  tidak bisa masuk. Tapi napasnya terbatas — habis napas, pemain
	  DIKELUARKAN dan bilik hangus sebentar.

	SEMUA nilai di bawah bisa di-override PER BILIK lewat Attribute pada
	Part bilik itu (nama Attribute = nama field di sini).
--]]

local Config = {}

-----------------------------------------------------------------
-- PENANDA DI STUDIO
-----------------------------------------------------------------
-- Cukup salah satu: beri tag pada Part, ATAU taruh Part di dalam
-- Folder bernama "SafeZones" di Workspace. Nama Part bebas.
Config.SafeZoneTag    = "SafeZone"
Config.SafeZoneFolder = "SafeZones"

-----------------------------------------------------------------
-- CARA MASUK
-----------------------------------------------------------------
-- false (default) = ProximityPrompt. Pemain menekan tombol untuk
--   sembunyi; karakter dipindah ke dalam bilik + kamera mengintip.
--   Ini mode untuk bilik toilet / lemari.
-- true = cukup berdiri di dalam area (perilaku lama). Untuk ruang aman
--   terbuka yang luas, di mana "sembunyi" tidak masuk akal.
Config.TouchToEnter = false

-- Teks yang DILIHAT PEMAIN: bahasa Inggris (permintaan Aer).
-- Komentar & nama variabel tetap Indonesia untuk tim.
Config.PromptActionText   = "Hide"
Config.PromptExitText     = "Leave"
Config.PromptObjectText   = ""      -- kosong = tidak menampilkan nama objek
Config.PromptDistance     = 9       -- MaxActivationDistance (studs)
Config.PromptHoldDuration = 0       -- >0 = harus tahan tombol
Config.PromptKey          = Enum.KeyCode.E
-- Pintu toilet itu mesh padat; kalau LOS diwajibkan, prompt-nya sering
-- tidak muncul walau pemain berdiri tepat di depannya.
Config.PromptRequiresLineOfSight = false

-----------------------------------------------------------------
-- SEMBUNYI: posisi karakter, kamera mengintip, pintu keluar
-----------------------------------------------------------------
-- Child OPSIONAL di dalam Part bilik untuk mengatur titik secara presisi.
-- Kalau tidak ada, semuanya dihitung dari ukuran & arah hadap Part.
Config.HidePointName = "HidePoint"  -- di mana karakter berdiri
Config.PeekPointName = "PeekPoint"  -- di mana kamera mengintip
Config.ExitPointName = "ExitPoint"  -- ke mana pemain dikeluarkan

Config.HideFeetOffset = 3.0   -- tinggi root R15 dari lantai (studs)
Config.PeekEyeHeight  = 1.4   -- tinggi mata dari root karakter
Config.PeekOutward    = 0.4   -- geser kamera keluar dari muka pintu
Config.ExitPush       = 4.0   -- jarak lempar keluar dari muka pintu

-- Kunci karakter di tempat. Anchored = paling andal (tidak bisa terdorong
-- monster / physics), WalkSpeed 0 saja masih bisa tergeser.
Config.HideAnchor = true

-- Batas mengintip (derajat). Kamera tidak bebas 360 — ia terkurung di
-- balik pintu, jadi cuma bisa melirik.
-- YawLimit = SETENGAH dari rentang total: 60 berarti pemain bisa menengok
-- 60 kiri + 60 kanan = 120 derajat (permintaan Aer).
Config.PeekYawLimit   = 60
Config.PeekPitchLimit = 25
-- Derajat per piksel gerakan mouse. 0.25 terlalu lambat untuk rentang 120.
Config.PeekSensitivity = 0.4

-- Lama pesan penolakan ("stall is spent") tampil sebelum disembunyikan.
-- Pemain yang DITOLAK tidak pernah jadi penghuni, jadi tanpa timer ini
-- tidak ada apa pun yang akan membersihkan UI-nya.
Config.DeniedNoticeTime = 1.6

-- Transisi gelap saat masuk/keluar. Ini PENGGANTI SEMENTARA animasi
-- masuk-bilik & animasi monster menarik keluar (belum ada asetnya).
Config.FadeTime = 0.35

-----------------------------------------------------------------
-- NAPAS (anti-camping)
-----------------------------------------------------------------
Config.BreathTime   = 20   -- lama perlindungan satu bilik (detik)
Config.MaxOccupants = 1    -- 1 = bilik toilet (rebutan)
Config.CooldownTime = 15   -- lama bilik "hangus" sebelum napas penuh lagi

-- true  = keluar sebelum napas habis pun langsung menghanguskan bilik.
-- false = bilik boleh langsung dipakai lagi, TAPI napasnya tidak terisi
--         ulang (sisa napas dilanjutkan). Ini yang mencegah exploit
--         keluar-masuk untuk mereset timer.
Config.BurnOnExit = false

-----------------------------------------------------------------
-- DINDING TAK TERLIHAT (monster ditahan di luar)
-----------------------------------------------------------------
Config.BarrierEnabled = true
Config.BarrierGroup   = "SafeZoneShield"
Config.MonsterGroup   = "MonsterBody"

-----------------------------------------------------------------
-- LAPORAN KE CLIENT (UI bar napas + kamera mengintip)
-----------------------------------------------------------------
Config.RemoteName   = "SafeZoneState"  -- RemoteEvent di ReplicatedStorage
Config.TickInterval = 0.1              -- detak server (detik)

-----------------------------------------------------------------
-- STATE BILIK (dipakai internal + dikirim ke UI)
-----------------------------------------------------------------
Config.State = {
	READY    = "READY",     -- kosong, siap dipakai
	OCCUPIED = "OCCUPIED",  -- ada yang sembunyi, napas berkurang
	BREACHED = "BREACHED",  -- napas habis, penghuni dikeluarkan
	COOLDOWN = "COOLDOWN",  -- hangus, belum bisa dipakai
}

-- Jenis pesan ke client
Config.Event = {
	STATE = "STATE",   -- pembaruan bar napas
	ENTER = "ENTER",   -- pemain masuk: fade + kamera mengintip
	EXIT  = "EXIT",    -- pemain keluar: fade + kamera normal
}

-----------------------------------------------------------------
-- OVERRIDE PER BILIK (Attribute pada Part bilik)
-----------------------------------------------------------------
--[[
	Number (harus >= 0):
	  BreathTime    lama perlindungan bilik ini
	  MaxOccupants  kapasitas bilik ini (dibulatkan; minimal 1)
	  CooldownTime  lama hangus bilik ini

	Bool:
	  TouchToEnter  masuk cukup dengan berdiri di dalam (tanpa prompt)
	  BurnOnExit    keluar lebih awal langsung menghanguskan bilik
	  NoBarrier     bilik ini TIDAK menahan monster
	  NoBreath      bilik ini aman SELAMANYA (tanpa timer)

	Nilai salah tipe / negatif diabaikan + warn sekali. Prinsipnya sama
	dengan sistem lain di project ini: satu salah ketik tidak boleh
	menjatuhkan seluruh bilik.
--]]
Config.NumberOverrides = {
	BreathTime   = true,
	MaxOccupants = true,
	CooldownTime = true,
}

Config.BoolOverrides = {
	TouchToEnter = true,
	BurnOnExit   = true,
	NoBarrier    = true,
	NoBreath     = true,
}

return Config
