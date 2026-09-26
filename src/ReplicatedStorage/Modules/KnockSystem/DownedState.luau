--[[
	DownedState.luau
	----------------
	Mengelola KONDISI "tumbang" (knocked) pada karakter pemain.

	Tanggung jawab:
	  1. Menahan Humanoid tetap hidup di 0 HP (state DEAD dimatikan).
	  2. Registry pemain yang sedang tumbang = SATU sumber kebenaran.
	  3. Menandai karakter lewat Attribute supaya tim/SFX/UI bisa membacanya.
	  4. Melepas kondisi: memulihkan (revive) atau membunuh beneran (bleed-out).

	PENTING (terbukti empiris, lihat header Config.luau):
	  State DEAD dimatikan SEBELUM Health menyentuh 0. Tanpa itu Humanoid
	  langsung ragdoll dan tidak bisa ditolong lagi.
--]]

local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local DownedState = {}

--- Registry: [character] = { player, humanoid, character, since, deadline, warned }
local registry: { [Model]: any } = {}

-----------------------------------------------------------------
-- QUERY
-----------------------------------------------------------------
function DownedState.isDowned(character: Model?): boolean
	if not character then
		return false
	end
	return registry[character] ~= nil
end

function DownedState.isPlayerDowned(player: Player?): boolean
	if not player then
		return false
	end
	return DownedState.isDowned(player.Character)
end

function DownedState.getRecord(character: Model?): any
	if not character then
		return nil
	end
	return registry[character]
end

--- Salinan daftar penghuni (aman di-iterasi sambil diubah di dalam loop).
function DownedState.getAll(): { [Model]: any }
	return registry
end

function DownedState.count(): number
	local n = 0
	for _ in registry do
		n += 1
	end
	return n
end

-----------------------------------------------------------------
-- ANTI-MATI (persenjataan Humanoid)
-----------------------------------------------------------------
--- Matikan state DEAD supaya Health boleh menyentuh 0 tanpa ragdoll.
--- Dipanggil saat karakter SPAWN, bukan saat damage masuk, supaya tidak ada
--- satu frame pun di mana Humanoid sempat mati duluan.
function DownedState.armAntiDeath(humanoid: Humanoid?): boolean
	if not humanoid or not humanoid.Parent then
		return false
	end
	local ok = pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end)
	return ok
end

--- Kembalikan kemampuan mati (dipakai saat mati beneran).
function DownedState.disarmAntiDeath(humanoid: Humanoid?): boolean
	if not humanoid or not humanoid.Parent then
		return false
	end
	local ok = pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	end)
	return ok
end

-----------------------------------------------------------------
-- MASUK KONDISI TUMBANG
-----------------------------------------------------------------
--- Masuk kondisi tumbang. Mengembalikan record, atau nil bila tidak valid.
function DownedState.enter(character: Model, humanoid: Humanoid): any
	if registry[character] then
		return nil -- sudah tumbang, jangan dobel
	end
	if not character.Parent or not humanoid.Parent then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	local bleedOut = Config.get(player, "BleedOutTime")

	local rec = {
		player    = player,
		humanoid  = humanoid,
		character = character,
		since     = os.clock(),
		deadline  = os.clock() + bleedOut,
		warned    = false,
	}
	registry[character] = rec

	-- Pastikan anti-death aktif (mis. karakter di-spawn sebelum sistem siap).
	DownedState.armAntiDeath(humanoid)

	-- Tahan di minimum 1 HP (bukan 0) agar engine Roblox (PlayerModule / ControlScript)
	-- tidak mematikan input gerakan WASD/analog mobile pemain saat tumbang.
	humanoid.Health = math.clamp(humanoid.Health, 1, 100)

	-- Penanda untuk tim (replikasi otomatis ke client).
	character:SetAttribute(Config.DownedAttribute, true)
	character:SetAttribute(Config.BleedOutAttribute, bleedOut)
	character:SetAttribute(Config.ReviveProgressAttribute, 0)

	return rec
end

-----------------------------------------------------------------
-- KELUAR KONDISI TUMBANG
-----------------------------------------------------------------
--- Bangunkan pemain (revive). Mengembalikan true bila berhasil.
function DownedState.revive(character: Model, humanoid: Humanoid?): boolean
	local rec = registry[character]
	if not rec then
		return false
	end
	registry[character] = nil

	local h = humanoid or rec.humanoid
	local health = math.max(1, Config.get(rec.player, "ReviveHealth"))

	-- Kemampuan mati dikembalikan SEBELUM Health diisi, supaya pemain kembali
	-- ke kondisi normal (bisa mati lagi kalau dipukul).
	DownedState.disarmAntiDeath(h)
	h.Health = health

	character:SetAttribute(Config.DownedAttribute, false)
	character:SetAttribute(Config.BleedOutAttribute, 0)
	character:SetAttribute(Config.ReviveProgressAttribute, 0)

	return true
end

--- Mati BENERAN (bleed-out habis). Karakter mati seperti biasa.
function DownedState.kill(character: Model, humanoid: Humanoid?): boolean
	local rec = registry[character]
	if not rec then
		return false
	end
	registry[character] = nil

	local h = humanoid or rec.humanoid

	character:SetAttribute(Config.DownedAttribute, false)
	character:SetAttribute(Config.BleedOutAttribute, 0)
	character:SetAttribute(Config.ReviveProgressAttribute, 0)

	-- Resep mati beneran (terbukti di runtime): state DEAD dinyalakan lagi.
	-- JEBAKAN: pemain tumbang sudah di Health 0, jadi set Health=0 sekali lagi
	-- BUKAN perubahan -> HealthChanged tidak terbit -> tidak mati. Harus
	-- memaksa transisi state secara eksplisit.
	DownedState.disarmAntiDeath(h)
	if h and h.Parent then
		if h.Health > 0 then
			h.Health = 0
		else
			pcall(function()
				h:ChangeState(Enum.HumanoidStateType.Dead)
			end)
		end
	end

	return true
end

--- Lupakan karakter (respawn / keluar). TIDAK membunuh; hanya bersih-bersih.
--- Anti-death tetap dilepas supaya karakter berikutnya tidak mewarisi kondisi.
function DownedState.forget(character: Model?)
	if not character then
		return
	end
	local rec = registry[character]
	registry[character] = nil

	if rec and rec.humanoid and rec.humanoid.Parent then
		DownedState.disarmAntiDeath(rec.humanoid)
	end

	if character.Parent then
		character:SetAttribute(Config.DownedAttribute, false)
		character:SetAttribute(Config.BleedOutAttribute, 0)
		character:SetAttribute(Config.ReviveProgressAttribute, 0)
	end
end

--- Khusus uji perilaku. Jangan dipanggil saat runtime.
function DownedState.reset()
	registry = {}
end

return DownedState
