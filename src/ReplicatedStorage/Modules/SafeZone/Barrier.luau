--[[
	Barrier.luau
	------------
	Dinding tak terlihat: bilik jadi SOLID khusus untuk monster selama
	masih melindungi, tapi pemain tetap bisa jalan masuk-keluar.

	KENAPA CollisionGroup, bukan CanCollide:
	  CanCollide = true akan menahan SEMUA benda, termasuk pemain yang mau
	  masuk bilik. Yang kita butuh adalah tabrakan SELEKTIF. Roblox
	  menyediakan itu lewat CollisionGroup: dua grup, satu aturan.

	  MonsterGroup   x BarrierGroup = true   (monster mentok)
	  BarrierGroup   x Default      = false  (pemain & benda lain lewat)
	  BarrierGroup   x BarrierGroup = false  (bilik tidak saling dorong)

	Grup asli setiap part DISIMPAN sebelum diubah dan dipulihkan saat
	unregister — script ini dipakai di place yang dibangun tim lain,
	jadi tidak boleh menimpa setelan orang secara permanen.
--]]

local PhysicsService = game:GetService("PhysicsService")

local Config = require(script.Parent.Config)

local Barrier = {}

local ready = false

-- part -> { group = string, canCollide = boolean }
local original: { [BasePart]: { group: string, canCollide: boolean } } = {}

---------------------------------------------------------------------
-- SETUP GRUP (idempotent)
---------------------------------------------------------------------

local function registerGroup(name: string): boolean
	local ok = pcall(function()
		if PhysicsService:IsCollisionGroupRegistered(name) then
			return
		end
		PhysicsService:RegisterCollisionGroup(name)
	end)
	return ok
end

--- Siapkan collision group. Aman dipanggil berkali-kali.
--- @return boolean  false = physics API tidak tersedia; barrier dilewati
function Barrier.init(): boolean
	if ready then
		return true
	end

	if not registerGroup(Config.BarrierGroup) or not registerGroup(Config.MonsterGroup) then
		warn("[SafeZone] Gagal mendaftarkan CollisionGroup -> dinding monster dilewati.")
		return false
	end

	local ok = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(Config.BarrierGroup, Config.MonsterGroup, true)
		PhysicsService:CollisionGroupSetCollidable(Config.BarrierGroup, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(Config.BarrierGroup, Config.BarrierGroup, false)
	end)

	if not ok then
		warn("[SafeZone] Gagal mengatur aturan tabrakan CollisionGroup -> dinding monster dilewati.")
		return false
	end

	ready = true
	return true
end

---------------------------------------------------------------------
-- PART BILIK
---------------------------------------------------------------------

--- Catat setelan asli sebuah part bilik (sekali saja).
function Barrier.register(zonePart: BasePart)
	if original[zonePart] then
		return
	end
	original[zonePart] = {
		group = zonePart.CollisionGroup,
		canCollide = zonePart.CanCollide,
	}
end

--- Nyalakan / matikan dinding sebuah bilik.
--- @param solid  true = monster ditahan, false = monster boleh masuk
function Barrier.setSolid(zonePart: BasePart, solid: boolean)
	if not ready or not original[zonePart] then
		return
	end

	if solid then
		zonePart.CollisionGroup = Config.BarrierGroup
		zonePart.CanCollide = true
	else
		-- Napas habis / bilik kosong: benar-benar tembus, termasuk untuk monster.
		zonePart.CanCollide = false
		zonePart.CollisionGroup = original[zonePart].group
	end
end

--- Pulihkan setelan asli (dipakai saat bilik di-untag / dihapus).
function Barrier.unregister(zonePart: BasePart)
	local saved = original[zonePart]
	if not saved then
		return
	end
	if zonePart.Parent then
		zonePart.CanCollide = saved.canCollide
		zonePart.CollisionGroup = saved.group
	end
	original[zonePart] = nil
end

---------------------------------------------------------------------
-- BADAN MONSTER
---------------------------------------------------------------------

--- Masukkan semua part monster ke MonsterGroup supaya kena dinding.
--- Aman dipanggil ulang (nilai grup sama = tidak ada efek).
---
--- CATATAN: ini menyentuh CollisionGroup part monster. Grup MonsterGroup
--- tetap bertabrakan dengan Default, jadi monster masih menabrak lantai,
--- dinding asli, dan pemain seperti biasa — yang berubah hanya
--- kemampuannya melewati bilik.
function Barrier.markMonster(monsterModel: Model)
	if not ready then
		return
	end
	for _, part in monsterModel:GetDescendants() do
		if part:IsA("BasePart") and part.CollisionGroup == "Default" then
			part.CollisionGroup = Config.MonsterGroup
		end
	end
end

--- Lepas tanda monster (monster mati / di-untag).
function Barrier.unmarkMonster(monsterModel: Model)
	if not ready or not monsterModel.Parent then
		return
	end
	for _, part in monsterModel:GetDescendants() do
		if part:IsA("BasePart") and part.CollisionGroup == Config.MonsterGroup then
			part.CollisionGroup = "Default"
		end
	end
end

return Barrier
