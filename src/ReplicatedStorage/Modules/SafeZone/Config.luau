--[[
	Config.luau  (SafeZone)
	-----------------------
	Konfigurasi terpusat sistem Safe Zone "bilik toilet".

	KONSEP:
	  Safe Zone bukan lagi area aman permanen. Ia punya JATAH NAPAS.
	  Pemain masuk bilik -> monster tidak bisa menarget & tidak bisa masuk
	  (dinding tak terlihat). Napas habis -> perlindungan lepas, dinding
	  dibuka, monster boleh masuk. Setelah dipakai bilik HANGUS sebentar
	  (cooldown) sebelum bisa dipakai lagi.

	SEMUA nilai di bawah bisa di-override PER BILIK lewat Attribute pada
	Part bilik itu (nama Attribute = nama field di sini). Jadi satu bilik
	bisa 20 detik dan bilik lain 8 detik tanpa menyentuh script.
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
-- NAPAS (anti-camping)
-----------------------------------------------------------------
-- Lama perlindungan satu bilik, dalam detik.
Config.BreathTime = 20

-- Berapa orang boleh dilindungi satu bilik sekaligus.
-- 1 = bilik toilet (rebutan). Naikkan untuk ruangan besar.
Config.MaxOccupants = 1

-- Lama bilik "hangus" sebelum napasnya terisi penuh lagi (detik).
Config.CooldownTime = 15

-- true  = keluar sebelum napas habis pun langsung menghanguskan bilik.
-- false = bilik boleh langsung dipakai lagi, TAPI napasnya tidak terisi
--         ulang (sisa napas dilanjutkan). Ini yang mencegah exploit
--         keluar-masuk untuk mereset timer.
Config.BurnOnExit = false

-----------------------------------------------------------------
-- DINDING TAK TERLIHAT (monster ditahan di luar)
-----------------------------------------------------------------
-- Bilik jadi solid KHUSUS untuk monster selama masih melindungi.
-- Pemain tetap bisa lewat (pakai CollisionGroup, bukan CanCollide biasa).
Config.BarrierEnabled = true

-- Nama CollisionGroup. Ubah hanya kalau bentrok dengan grup lain di place.
Config.BarrierGroup = "SafeZoneShield"
Config.MonsterGroup = "MonsterBody"

-----------------------------------------------------------------
-- LAPORAN KE CLIENT (untuk UI bar napas)
-----------------------------------------------------------------
Config.RemoteName   = "SafeZoneState"  -- RemoteEvent di ReplicatedStorage
Config.TickInterval = 0.1              -- detak server (detik)

-----------------------------------------------------------------
-- STATE BILIK (dipakai internal + dikirim ke UI)
-----------------------------------------------------------------
Config.State = {
	READY    = "READY",     -- kosong, siap dipakai
	OCCUPIED = "OCCUPIED",  -- ada yang dilindungi, napas berkurang
	BREACHED = "BREACHED",  -- napas habis, perlindungan lepas
	COOLDOWN = "COOLDOWN",  -- hangus, belum bisa dipakai
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
	  BurnOnExit    keluar lebih awal langsung menghanguskan bilik
	  NoBarrier     bilik ini TIDAK menahan monster (cuma perlindungan
	                target), berguna untuk area aman terbuka
	  NoBreath      bilik ini aman SELAMANYA (perilaku lama, tanpa timer)

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
	BurnOnExit = true,
	NoBarrier  = true,
	NoBreath   = true,
}

return Config
