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

local MonsterRig = {}

--- Script animasi bawaan yang sering berebut Animator dengan AnimationManager.
local CONFLICTING_SCRIPTS = { Anim = true, Animate = true }

--- HipHeight yang membuat kaki napak, dihitung dari geometri RENDER sekarang.
---
--- Roblox meletakkan PUSAT root (`root.Position`) di `HipHeight` stud di atas
--- lantai. Jadi HipHeight yang benar = jarak dari PUSAT root ke titik TERENDAH
--- yang kelihatan pemain.
---
--- KENAPA `root.Size.Y*0.5` SALAH (bikin monster terbang): pada mesh badut,
--- collision box (`Size.Y`) sering JAUH lebih besar dari mesh visualnya
--- (contoh nyata: Size.Y=7.37 tapi mesh render cuma 1.61 stud, sisanya rongga).
--- Memakai setengah Size.Y menaruh pusat 3.68 stud di atas tanah padahal bawah
--- mesh cuma 0.80 stud dari pusat -> monster ngambang 2.88 stud.
--- Solusi: ukur dari `GetBoundingBox()` (kotak yang membungkus GEOMETRI render),
--- bukan dari Size.Y part.
local function computeHipHeight(model: Model, root: BasePart): number?
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not cf or not size then
		return nil
	end
	local renderBottom = cf.Position.Y - size.Y * 0.5
	-- Pusat root ke bawah render = HipHeight supaya bawah mesh menyentuh lantai.
	return root.Position.Y - renderBottom
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

--- Pastikan Humanoid punya Animator, dan singkirkan AnimationController yang
--- bentrok. Mengembalikan true bila AnimationController dihapus.
---
--- KENAPA: mesh hasil rig lama (pola "driver + skin") datang dengan
--- AnimationController + Animator sendiri. Begitu kita kasih Humanoid, ada DUA
--- kandidat penyetir: Humanoid.Animator (jalur AnimationManager) dan
--- AnimationController.Animator (jalur lama). Animasi yang di-load ke Animator
--- yang BUKAN penggerak mesh -> mesh diam di rest pose (T-pose). Humanoid selalu
--- menang untuk model ber-Humanoid, jadi AnimationController tinggal jadi
--- sumber kebingungan -> dibuang.
local function fixAnimator(model: Model, humanoid: Humanoid): boolean
	-- Humanoid wajib punya Animator (AnimationManager butuh ini).
	if not humanoid:FindFirstChildOfClass("Animator") then
		local a = Instance.new("Animator")
		a.Parent = humanoid
	end

	local removed = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationController") then
			d:Destroy()
			removed = true
		end
	end
	return removed
end

--- Siapkan monster ber-struktur baru. Idempotent (aman dipanggil ulang).
--- Mengembalikan ringkasan untuk dilaporkan ke Output.
function MonsterRig:setup(model: Model): { [string]: any }
	local result = {
		hipHeight = nil :: number?,
		hipHeightBefore = nil :: number?,
		collisionOn = 0,
		scriptsDisabled = {},
		animControllerRemoved = false,
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

	-- 1b. Satu penyetir animasi saja: Humanoid.Animator. Buang AnimationController
	--     sisa rig lama supaya animasi benar-benar menggerakkan mesh (bukan T-pose).
	result.animControllerRemoved = fixAnimator(model, humanoid)

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
