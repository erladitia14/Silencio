--!strict
--[[
	BatteryPuzzleController — orchestrator SERVER (Script di ServerScriptService).

	Menyambung 4 modul BatteryPuzzle. Berdiri SENDIRI:
	- tidak require EnemyController / KeySystem / SafeZone
	- tidak mengubah script sistem lain

	Cara pakai (nol konfigurasi, cukup tag di Tag Editor):
	  Model wadah   -> tag "BatteryCase"
	  Placeholder   -> tag "BatterySlot"   (BasePart, diposisikan manual)
	  Baterai asli  -> tag "BatteryPickup" (BasePart yang bisa diambil)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BatteryPuzzle = Modules:WaitForChild("BatteryPuzzle")

local Config = require(BatteryPuzzle:WaitForChild("Config"))
local BatteryService = require(BatteryPuzzle:WaitForChild("BatteryService"))
local CaseService = require(BatteryPuzzle:WaitForChild("CaseService"))
local PuzzleService = require(BatteryPuzzle:WaitForChild("PuzzleService"))

-- ============================================================
-- RemoteEvent (progress ke client; opsional dipakai UI)
-- ============================================================

local remote = ReplicatedStorage:FindFirstChild("BatteryPuzzleEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "BatteryPuzzleEvent"
	remote.Parent = ReplicatedStorage
end

-- ============================================================
-- START (hanya di server)
-- ============================================================

if not RunService:IsServer() then
	return
end

-- PuzzleService dulu: menyiapkan event per-case
PuzzleService.start()

-- CaseService butuh fungsi dari BatteryService (lewat orchestrator,
-- supaya modul tidak saling require)
CaseService.start({
	getCarried = function(player)
		return BatteryService.getCarried(player)
	end,
	consumeCarried = function(player)
		return BatteryService.consume(player)
	end,
	onSlotFilled = function(player, case, slot)
		local filled, total = CaseService.getProgress(case)
		PuzzleService.reportSlotFilled(case, slot, filled, total)
	end,
})

-- BatteryService
BatteryService.start()

-- ============================================================
-- SAAT GAME BERJALAN: sembunyikan placeholder
-- ============================================================

-- Di Studio edit mode placeholder TETAP terlihat supaya bisa ditata.
-- Begitu game jalan, baru disembunyikan (tidak dihapus).
CaseService.hidePlaceholders()

Config.log("BatteryPuzzleController ready")
