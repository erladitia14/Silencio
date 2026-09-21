--!strict
--[[
	MonsterRig.luau
	---------------
	Menyiapkan monster ber-STRUKTUR BARU (satu model, tanpa skin terpisah).

	STRUKTUR BARU (permintaan Aer, 21 Sep 2026):
	  Enemies/
	  └── Clown              <- tag "Monster", Model
	      ├── HumanoidRootPart  = MeshPart badut (mesh + bone/animasi)
	      └── Humanoid

	Beda dari pola lama "driver + skin" (SkinBinder): dulu rig R15 tipis di-weld
	ke mesh kulit terpisah, dan mesh dibuat CanCollide=false supaya tidak menahan
	rig. Akibatnya mesh visual nyembul keluar dari collision hitbox tipis ->
	terlihat menembus tembok/tanah. Sekarang MESH-nya SENDIRI yang jadi
	HumanoidRootPart, jadi tidak ada lagi yang nembus.

	YANG DIKERJAKAN MODUL INI (idempotent, cukup tag "Monster"):
	  1. Collision mesh dinyalakan (CanCollide = true) supaya tidak menembus.
	     Bisa di-skip dengan Attribute "KeepCollision" (biar tim yang atur).
	  2. Satu penyetir animasi saja: pastikan Humanoid punya Animator, dan buang
	     AnimationController sisa rig lama yang bikin animasi diam (T-pose).
	  3. Matikan LocalScript "Animate"/"Anim" bawaan yang ikut merebut Animator.

	PENTING — POSISI & HipHeight TIDAK DISENTUH.
	Modul ini TIDAK mengubah HipHeight dan TIDAK memindahkan part apa pun.
	Tinggi badan monster sepenuhnya urusan tim yang menata di Studio: letakkan
	monster pada posisi yang benar, nilainya dipakai apa adanya.
	(Menebak HipHeight dari geometri mesh sudah dicoba dan SALAH untuk skinned
	mesh: bone yang menggerakkan mesh tidak sejalan dengan kotak part, jadi
	hitung-hitungan malah mengangkat/menenggelamkan monster.)

	OPT-OUT (Attribute pada Model):
	  - "KeepCollision" = true    -> jangan sentuh CanCollide part
]]

local MonsterRig = {}

--- Script animasi bawaan yang sering berebut Animator dengan AnimationManager.
local CONFLICTING_SCRIPTS = { Anim = true, Animate = true }

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
--- TIDAK menyentuh HipHeight / posisi part.
--- Mengembalikan ringkasan untuk dilaporkan ke Output.
function MonsterRig:setup(model: Model): { [string]: any }
	local result = {
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

	-- 2. Satu penyetir animasi saja: Humanoid.Animator. Buang AnimationController
	--    sisa rig lama supaya animasi benar-benar menggerakkan mesh (bukan T-pose).
	result.animControllerRemoved = fixAnimator(model, humanoid)

	-- 3. Collision ON (kecuali tim minta atur sendiri).
	if model:GetAttribute("KeepCollision") ~= true then
		result.collisionOn = enableCollision(model)
	end

	-- CATATAN: HipHeight & posisi TIDAK diubah di sini (lihat header).

	return result
end

return MonsterRig
