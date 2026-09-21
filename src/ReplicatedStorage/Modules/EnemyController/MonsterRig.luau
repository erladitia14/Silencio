--!strict
--[[
	MonsterRig.luau
	---------------
	Menyiapkan monster ber-STRUKTUR BARU (satu model, tanpa skin terpisah).

	STRUKTUR BARU (permintaan Aer, 21 Sep 2026):
	  Enemies/
	  └── Clown              <- tag "Monster", Model
	      ├── HumanoidRootPart  = MeshPart badut (mesh + bone/animasi)  <- CanCollide ON
	      └── Humanoid

	Beda dari pola lama "driver + skin" (SkinBinder): dulu rig R15 tipis di-weld
	ke mesh kulit terpisah, dan mesh dibuat CanCollide=false supaya tidak menahan
	rig. Akibatnya mesh visual nyembul keluar dari collision hitbox tipis ->
	terlihat menembus tembok/tanah. Sekarang MESH-nya SENDIRI yang jadi
	HumanoidRootPart dengan collision nyala, jadi tidak ada lagi yang nembus.

	YANG DIKERJAKAN MODUL INI (idempotent, cukup tag "Monster"):
	  1. HipHeight OTOMATIS dari geometri, supaya kaki napak (tidak tenggelam /
	     melayang) tanpa mengisi angka manual. Rumus tervalidasi:
	       HipHeight = (root bawah) - (titik terendah seluruh part model)
	     Untuk model 1-part (mesh = root) hasilnya 0 -> pusat mesh di tanah,
	     jadi ditambah setengah tinggi mesh supaya bawah mesh yang menyentuh lantai.
	  2. Collision mesh dinyalakan (CanCollide = true) supaya tidak menembus.
	     Bisa di-skip dengan Attribute "KeepCollision" (biar tim yang atur).
	  3. Matikan LocalScript "Animate"/"Anim" bawaan yang berebut Animator
	     (hanya satu penyetir animasi; AnimationManager yang pegang).

	OPT-OUT (Attribute pada Model):
	  - "AutoHipHeight" = false   -> jangan hitung HipHeight otomatis
	  - "KeepCollision" = true    -> jangan sentuh CanCollide part
	  - "HipHeightPadding" = <n>  -> geser HipHeight (+ = badan naik). Default 0.
]]

local RunService = game:GetService("RunService")

local MonsterRig = {}

--- Script animasi bawaan yang sering berebut Animator dengan AnimationManager.
local CONFLICTING_SCRIPTS = { Anim = true, Animate = true }

--- Titik terendah (Y dunia) dari seluruh BasePart dalam model. math.huge bila
--- tidak ada part.
local function lowestPartY(model: Model): number
	local lo = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			lo = math.min(lo, d.Position.Y - d.Size.Y * 0.5)
		end
	end
	return lo
end

--- HipHeight yang membuat kaki napak, dihitung dari geometri sekarang.
--- Untuk R6 (model 1-part), Roblox meletakkan PUSAT root di HipHeight di atas
--- tanah; untuk R15, jarak root-bawah ke kaki. Rumus lowest-part menutup
--- kedua kasus: selisih antara bawah root dengan titik terendah model.
--- Model 1-part -> selisih 0 -> tambah setengah tinggi root supaya BAWAH mesh
--- yang menyentuh lantai, bukan pusatnya.
local function computeHipHeight(model: Model, root: BasePart): number?
	local lowest = lowestPartY(model)
	if lowest == math.huge then
		return nil
	end
	local rootBottom = root.Position.Y - root.Size.Y * 0.5
	local gap = rootBottom - lowest        -- jarak bawah-root ke kaki terendah
	-- Model 1-part: root ADALAH satu-satunya part -> gap = 0. Humanoid R6
	-- menaruh PUSAT root di HipHeight, jadi setengah tinggi root harus masuk.
	return gap + root.Size.Y * 0.5
end

--- Matikan LocalScript "Animate"/"Anim" bawaan di dalam model. Mengembalikan
--- daftar nama yang dimatikan.
local function disableConflictingScripts(model: Model): { string }
	local disabled = {}
	for _, d in ipairs(model:GetDescendants()) do
		if CONFLICTING_SCRIPTS[d.Name] and d:IsA("BaseScript") and d.Enabled then
			d.Enabled = false
			table.insert(disabled, d.Name)
		end
	end
	return disabled
end

--- Nyalakan collision semua BasePart model (mesh tidak lagi menembus).
--- Mengembalikan jumlah part yang diubah.
local function enableCollision(model: Model): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.CanCollide then
			d.CanCollide = true
			n += 1
		end
	end
	return n
end

--- Siapkan monster ber-struktur baru. Idempotent (aman dipanggil ulang).
--- Mengembalikan ringkasan untuk dilaporkan ke Output.
function MonsterRig:setup(model: Model): { [string]: any }
	local result = {
		hipHeight = nil :: number?,
		hipHeightBefore = nil :: number?,
		collisionOn = 0,
		scriptsDisabled = {},
	}

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		result.error = "model tidak punya Humanoid/HumanoidRootPart"
		return result
	end

	-- 1. Matikan script animasi bawaan yang bentrok (harus DULU: sebelum
	--    AnimationManager mengambil alih Animator).
	result.scriptsDisabled = disableConflictingScripts(model)

	-- 2. Collision ON (kecuali tim minta atur sendiri).
	if model:GetAttribute("KeepCollision") ~= true then
		result.collisionOn = enableCollision(model)
	end

	-- 3. HipHeight otomatis (kecuali di-opt-out).
	if model:GetAttribute("AutoHipHeight") ~= false then
		result.hipHeightBefore = humanoid.HipHeight
		local hip = computeHipHeight(model, root)
		if hip then
			local padding = tonumber(model:GetAttribute("HipHeightPadding")) or 0
			humanoid.HipHeight = hip + padding
			result.hipHeight = humanoid.HipHeight
		end
	end

	return result
end

return MonsterRig
