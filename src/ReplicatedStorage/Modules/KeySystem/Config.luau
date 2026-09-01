--[[
	Config.luau (KeySystem)
	-----------------------
	Konfigurasi terpusat untuk KEY SYSTEM.
	Semua nama Tag & nilai default disimpan di sini.

	FLOW: Kunci -> Pintu control room kebuka -> Power switch aktif -> Lampu carnival nyala

	Builder cukup menempel Tag (via Tag Editor) & mengatur Attribute di Studio.
	Kalau Attribute tidak diisi, sistem memakai default di bawah ini.
--]]

local Config = {}

-----------------------------------------------------------------
-- TAGS (CollectionService)
-----------------------------------------------------------------
Config.KeyPickupTag    = "KeyPickup"     -- Kunci: Tool, Part, atau Model
Config.LockedDoorTag   = "LockedDoor"    -- Pintu yang butuh kunci
Config.PowerSwitchTag  = "PowerSwitch"   -- Tuas/tombol power
Config.CarnivalLightTag = "CarnivalLight" -- Semua lampu carnival

-----------------------------------------------------------------
-- ATTRIBUTE NAMES (dibaca dari objek ber-tag)
-----------------------------------------------------------------
-- KeyPickup:
--   KeyId (string)        -> id kunci, default "control_room"
--   KeepInWorld (boolean) -> jangan hapus/pindahkan kunci setelah diambil
-- LockedDoor:
--   DoorId (string)       -> id pintu, default "control_room"
--   RequiredKey (string)  -> KeyId yang dibutuhkan, default = DoorId
--   AutoClose (boolean)   -> pintu menutup lagi otomatis, default false
--   AutoCloseDelay (num)  -> delay auto-close (detik), default 4
-- PowerSwitch:
--   RequiresDoorOpen (bool) -> butuh pintu kebuka dulu, default true
--   GateDoorId (string)     -> DoorId yang harus kebuka, default "control_room"
-- CarnivalLight:
--   OnBrightness (num)   -> OVERRIDE brightness saat nyala; kosong = pakai
--                           nilai asli yang sudah di-set tim (dianjurkan)
--   OffBrightness (num)  -> > 0 = lampu diredupkan, bukan dimatikan total;
--                           kosong/0 = Light.Enabled = false
--   KeepMaterial (bool)  -> jangan Neon-kan part yang tidak punya objek Light

-----------------------------------------------------------------
-- DEFAULTS
-----------------------------------------------------------------
Config.DefaultKeyId          = "control_room"
Config.DefaultDoorId         = "control_room"
Config.DefaultGateDoorId     = "control_room"

Config.DefaultAutoClose      = false
Config.DefaultAutoCloseDelay = 4

-- Pintu: cara "membuka" secara default (tanpa animasi rumit)
Config.DoorOpenTransparency  = 1     -- transparan saat terbuka
Config.DoorOpenCanCollide    = false -- bisa dilewati saat terbuka

-- Kunci berupa Tool: masuk Backpack pemain (muncul di hotbar, bisa dipegang)
-- alih-alih dihapus dari dunia. Kunci non-Tool (Part/Model) tetap dihapus.
-- false = semua kunci dihapus setelah diambil (perilaku lama).
Config.KeyToolToBackpack     = true

-- Matikan auto-pickup engine pada Handle kunci (Tool di Workspace otomatis
-- masuk Backpack begitu disentuh karakter, MELEWATI prompt -> KeyService tidak
-- tercatat dan pintu tetap terkunci). true = prompt jadi satu-satunya jalur.
Config.KeyToolBlockTouchPickup = true

-- Lampu
-- CATATAN: brightness lampu TIDAK dipaksa dari sini. LightManager memakai
-- nilai Brightness asli yang sudah di-set tim, jadi "nyala" = seperti niat
-- mereka. Attribute OnBrightness/OffBrightness per-objek untuk menimpanya.
-- LightOnColor hanya dipakai pada fallback Neon (objek ber-tag yang sama
-- sekali tidak punya objek Light di dalamnya).
Config.LightOnColor          = Color3.fromRGB(255, 236, 190) -- warna hangat carnival

-----------------------------------------------------------------
-- PROMPT (ProximityPrompt) TEKS
-----------------------------------------------------------------
Config.PromptKeyPickup       = "Ambil Kunci"
Config.PromptDoorUnlock      = "Buka Pintu"
Config.PromptDoorLocked      = "Terkunci — Butuh Kunci"
Config.PromptSwitchOn        = "Nyalakan Power"
Config.PromptSwitchLocked    = "Ruang Kontrol Masih Terkunci"
Config.PromptHoldDuration    = 0.6   -- durasi hold prompt (detik)
Config.PromptMaxDistance     = 8

return Config
