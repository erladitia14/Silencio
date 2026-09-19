--!strict
--[[
	Config — Battery Puzzle (Control Room 3)
	Semua angka yang bisa di-tune ada di sini. Modul lain membaca dari sini.
]]

local Config = {}

-- ============================================================
-- IDENTIFIKASI (pakai CollectionService tag — tahan rename)
-- ============================================================

Config.CaseTag = "BatteryCase"          -- Model wadah baterai
Config.SlotTag = "BatterySlot"          -- BasePart placeholder = titik pasang
Config.PickupTag = "BatteryPickup"      -- BasePart baterai yang bisa diambil

-- ============================================================
-- 1. BERAT — bawa baterai jadi lambat
-- ============================================================

Config.CarryWalkSpeed = 8               -- dari default 16 -> setengah
Config.CarryJumpPower = 30              -- dari default 50
Config.RestoreSpeedOnDrop = true        -- pulihkan ke nilai SEBELUM bawa

-- ============================================================
-- 2. WAKTU PASANG — harus diam, gak bisa gerak
-- ============================================================

Config.InsertDuration = 2.0             -- detik tahan prompt
Config.CancelInsertOnMove = false       -- true = batal kalau pemain jalan
Config.CancelInsertOnDamage = true      -- batal kalau kena damage

-- ============================================================
-- 3. INTERUPSI — baterai JATUH, bukan hilang
-- ============================================================

Config.DropOnDamage = true
Config.DropCooldown = 1.5               -- detik, cegah drop beruntun
Config.DroppedBatteryLifetime = 0       -- 0 = selamanya (jangan hilang!)

-- ============================================================
-- 4. SATU TANGAN — gak bisa pakai item lain
-- ============================================================

Config.MaxCarry = 1                     -- 1 baterai per pemain
-- Attribute yang diterbitkan ke Character saat membawa baterai.
-- Sistem lain (mis. flashlight) boleh MEMBACA ini untuk memblokir item.
-- Modul ini TIDAK mengubah script sistem lain.
Config.CarryingAttribute = "CarryingBattery"

-- ============================================================
-- 5. FAILURE & RECOVERY — puzzle tidak boleh macet
-- ============================================================

Config.ReturnOnDeath = true             -- baterai balik ke posisi awal
Config.ReturnOnLeave = true             -- pemain keluar server
Config.ReturnOnRespawn = true
Config.KeepBatteryOnDeath = false       -- false = kembali ke spawn

-- ============================================================
-- INTERAKSI
-- ============================================================

Config.PickupPromptText = "Pick Up"
Config.InsertPromptText = "Insert"
Config.PickupPromptDistance = 8
Config.InsertPromptDistance = 8
Config.PickupPromptKey = Enum.KeyCode.E
Config.InsertPromptKey = Enum.KeyCode.E
Config.RequireLineOfSight = false

-- ============================================================
-- VISUAL SAAT DIBAWA
-- ============================================================

-- Baterai asli TIDAK diubah ukurannya (biar tetap pas dengan slot).
-- Kalau perlu dikecilkan saat dibawa, set < 1. 1 = tidak diubah.
Config.CarryVisualScale = 1.0
Config.CarryOffset = CFrame.new(0, -0.6, -1.6)   -- relatif ke HumanoidRootPart
Config.HideOriginalWhileCarried = true           -- sembunyikan mesh asli, tampilkan salinan

-- ============================================================
-- PROGRESS
-- ============================================================

Config.CompletedAttribute = "BatteryPuzzleComplete"   -- di-set di Model case
Config.ProgressAttribute = "BatteryPuzzleProgress"    -- "2/4"
Config.BroadcastProgress = true         -- kirim progress ke semua client

-- ============================================================
-- DEBUG
-- ============================================================

Config.Debug = false
function Config.log(...: any)
	if Config.Debug then
		print("[BatteryPuzzle]", ...)
	end
end

return Config
