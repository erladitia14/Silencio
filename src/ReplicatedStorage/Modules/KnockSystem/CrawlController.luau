--[[
	CrawlController.luau
	--------------------
	Menerapkan perilaku fisik saat pemain tumbang: merangkak pelan, tidak bisa
	lompat, Tool dilepas. Dan MEMULIHKANNYA saat pemain dibangunkan.

	Prinsip: SIMPAN nilai asli sebelum menyentuh, PULIHKAN saat lepas. Kalau
	tidak, pemain yang keluar dari kondisi tumbang bisa "terkunci" lambat
	selamanya (pelajaran dari Occupancy SafeZone: forget yang meninggalkan
	Anchored=true bikin pemain terkunci permanen).
--]]

local Config = require(script.Parent.Config)

local CrawlController = {}

--- Snapshot nilai asli per karakter supaya bisa dipulihkan.
--- [character] = { walkSpeed, jumpPower, jumpHeight, useJumpPower }
local snapshots: { [Model]: any } = {}

-----------------------------------------------------------------
-- MASUK MODE MERANGKAK
-----------------------------------------------------------------
function CrawlController.apply(character: Model, humanoid: Humanoid)
	if snapshots[character] then
		return -- sudah dalam mode merangkak
	end

	snapshots[character] = {
		walkSpeed    = humanoid.WalkSpeed,
		jumpPower    = humanoid.JumpPower,
		jumpHeight   = humanoid.JumpHeight,
		useJumpPower = humanoid.UseJumpPower,
	}

	local player = nil
	do
		local Players = game:GetService("Players")
		player = Players:GetPlayerFromCharacter(character)
	end

	humanoid.WalkSpeed = math.max(0, Config.get(player, "CrawlSpeed"))

	if Config.get(player, "DisableJump") then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		-- Cegah lompatan yang sedang berlangsung.
		pcall(function()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		end)
	end

	if Config.DropTools then
		-- Lepas Tool yang sedang di-equip (jadi child Character saat equip).
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				humanoid:UnequipTools()
				break
			end
		end
	end
end

-----------------------------------------------------------------
-- KELUAR MODE MERANGKAK (revive / respawn / mati)
-----------------------------------------------------------------
function CrawlController.restore(character: Model?, humanoid: Humanoid?)
	if not character then
		return
	end
	local snap = snapshots[character]
	snapshots[character] = nil
	if not snap then
		return
	end

	local h = humanoid
	if not h and character.Parent then
		h = character:FindFirstChildOfClass("Humanoid")
	end
	if not h or not h.Parent then
		return
	end

	h.WalkSpeed    = snap.walkSpeed
	h.JumpPower    = snap.jumpPower
	h.JumpHeight   = snap.jumpHeight
	h.UseJumpPower = snap.useJumpPower

	pcall(function()
		h:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		h:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
	end)
end

--- Penjaga: WalkSpeed dipaksa ke nilai merangkak tiap tick. Sistem lain
--- (SafeZone, dll) atau engine bisa menimpanya; ini menjaga tetap pelan
--- selama pemain masih tumbang.
function CrawlController.enforce(character: Model, humanoid: Humanoid)
	if not snapshots[character] then
		return
	end
	if not humanoid or not humanoid.Parent then
		return
	end
	local Players = game:GetService("Players")
	local player = Players:GetPlayerFromCharacter(character)
	local target = math.max(0, Config.get(player, "CrawlSpeed"))
	if math.abs(humanoid.WalkSpeed - target) > 0.01 then
		humanoid.WalkSpeed = target
	end
end

function CrawlController.isCrawling(character: Model?): boolean
	if not character then
		return false
	end
	return snapshots[character] ~= nil
end

--- Khusus uji.
function CrawlController.reset()
	snapshots = {}
end

return CrawlController
