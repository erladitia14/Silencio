--[[
	SkinBinder.luau
	---------------
	Menyatukan RIG (yang punya Humanoid + AI) dengan MESH VISUAL (kulit).

	POLA "driver + skin":
	  Sebuah NPC bisa terdiri dari dua model terpisah di folder yang sama:

	    Folder induk (mis. "Clown")
	    ├── Hitbox   <- tag "Monster"      : rig R15 + Humanoid. Jalan, damage, tabrakan.
	    └── Clown    <- tag "MonsterSkin"  : mesh visual + animasi. Cuma tampilan.

	  Rig menyetir, mesh cuma menempel dan ikut. Berguna untuk karakter yang
	  di-import dari luar (Mixamo dsb) yang tidak bisa langsung jadi rig R15.

	YANG DIKERJAKAN MODUL INI (otomatis, cukup dua tag):
	  1. Weld tiap BasePart skin ke HumanoidRootPart milik rig
	  2. Skin: CanCollide = false + Massless = true
	     (tabrakan adalah tugas rig; mesh solid akan menahan gerak NPC)
	  3. Rig: semua part jadi Transparency = 1 (kerangka jadi tak terlihat)
	  4. Matikan script animasi lama di skin yang berebut Animator
	     (hanya SATU pihak boleh menyetir animasi)
	  5. Luruskan arah hadap skin ke rig sebelum weld (mesh import sering
	     melenceng 90 derajat; kalau dibiarkan, NPC jalan maju tapi badannya
	     menyamping karena weld membekukan selisih itu)
	  6. Pasang SkinAnimator supaya animasi skin mengikuti AIState rig

	PASANGAN DITENTUKAN DARI PARENT YANG SAMA. Jadi satu folder = satu NPC.
	Kalau satu folder berisi lebih dari satu skin, semuanya di-weld: tidak ada
	cara aman untuk menebak mana yang dimaksud.

	HANYA SAAT RUN: penyembunyian rig (Transparency = 1) cuma dilakukan ketika
	game berjalan. Kalau diterapkan di edit mode, nilainya ikut TERSIMPAN ke
	file place dan rig hilang selamanya dari viewport — padahal di edit mode rig
	perlu terlihat untuk diposisikan/di-skala.

	OPT-OUT:
	  - Attribute "KeepRigVisible" = true pada rig  -> jangan sembunyikan rig
	  - Attribute "KeepSkinCollision" = true pada rig -> jangan sentuh CanCollide skin
	  - Attribute "KeepSkinOrientation" = true pada rig -> jangan putar skin
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SkinAnimator = require(script.Parent.SkinAnimator)

local SkinBinder = {}

--- Tag untuk mesh visual. Rig tetap memakai Config.MonsterTag ("Monster").
SkinBinder.SkinTag = "MonsterSkin"

--- Skin yang sudah ter-bind per rig.
--- PENTING untuk raycast Line of Sight: skin berada di LUAR model rig
--- (sibling, bukan anak), jadi tanpa daftar ini raycast deteksi akan
--- menabrak badan visual monster sendiri dan menganggap pandangan
--- terhalang -> monster jadi buta permanen.
local boundSkins: { [Model]: { Instance } } = {}

--- Animator aktif per skin, supaya bisa dilepas saat monster dibersihkan.
local skinAnimators: { [Instance]: any } = {}

--- Instance yang harus dikecualikan dari raycast milik monster ini:
--- rig itu sendiri + semua skin yang menempel padanya.
function SkinBinder:getIgnoreList(rig: Model): { Instance }
	local list = { rig }
	for _, skin in boundSkins[rig] or {} do
		if skin.Parent then
			table.insert(list, skin)
		end
	end
	return list
end

--- Script animasi bawaan/lama yang sering berebut Animator (set, bukan array:
--- satu lintasan descendant cukup).
local CONFLICTING_SCRIPTS = { Anim = true, Animate = true }

--- Cari model skin yang berpasangan dengan rig: ber-tag SkinTag DAN
--- berada di parent yang sama, tapi bukan rig itu sendiri.
function SkinBinder:findSkins(rig: Model): { Instance }
	local parent = rig.Parent
	if not parent then
		return {}
	end

	local skins = {}
	for _, tagged in CollectionService:GetTagged(self.SkinTag) do
		if tagged ~= rig and tagged.Parent == parent then
			table.insert(skins, tagged)
		end
	end
	return skins
end

--- Kumpulkan semua BasePart di dalam sebuah skin (skin bisa Model/Folder/Part).
local function collectParts(skin: Instance): { BasePart }
	local parts = {}
	if skin:IsA("BasePart") then
		table.insert(parts, skin)
	end
	for _, d in skin:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

--- Apakah dua part sudah terhubung WeldConstraint? Weld bisa diparent di sisi
--- mana pun, jadi periksa anak keduanya. Dipakai agar bind() idempotent.
local function isWeldedTo(a: BasePart, b: BasePart): boolean
	for _, host in { a, b } do
		for _, d in host:GetChildren() do
			if d:IsA("WeldConstraint")
				and (d.Part0 == a or d.Part1 == a)
				and (d.Part0 == b or d.Part1 == b)
			then
				return true
			end
		end
	end
	return false
end

--- Matikan script animasi lama di dalam skin supaya tidak berebut Animator
--- dengan sistem animasi AI. Mengembalikan daftar nama yang dimatikan.
local function disableConflictingScripts(skin: Instance): { string }
	local disabled = {}
	for _, d in skin:GetDescendants() do
		if CONFLICTING_SCRIPTS[d.Name] and d:IsA("BaseScript") and d.Enabled then
			d.Enabled = false
			table.insert(disabled, d.Name)
		end
	end
	return disabled
end

--- Bongkar weld skin<->root yang sudah ada. Dipakai ketika orientasi skin baru
--- dikoreksi: weld lama masih memegang offset yang salah, jadi harus dibuat
--- ulang. Mengembalikan jumlah weld yang dihapus.
local function removeSkinWelds(skin: Instance, root: BasePart): number
	local n = 0
	local parts = collectParts(skin)
	local lookup: { [BasePart]: true } = {}
	for _, p in parts do
		lookup[p] = true
	end

	-- Weld bisa diparent di sisi mana pun: periksa root dan tiap part skin.
	local scan = { root }
	for _, p in parts do
		table.insert(scan, p)
	end
	for _, host in scan do
		for _, d in host:GetChildren() do
			if d:IsA("WeldConstraint") then
				local a, b = d.Part0, d.Part1
				local joinsSkinToRoot = (a == root and b and lookup[b])
					or (b == root and a and lookup[a])
				if joinsSkinToRoot then
					d:Destroy()
					n += 1
				end
			end
		end
	end
	return n
end

--- Toleransi selisih sudut hadap yang dianggap "sudah lurus" (derajat).
local ALIGN_TOLERANCE_DEG = 1.0

--- Cari acuan orientasi skin. Bone diutamakan karena SKELETON-lah yang
--- menentukan arah animasi, bukan CFrame MeshPart: mesh bisa tampak lurus
--- sementara tulangnya menghadap ke samping, sehingga animasinya menyamping.
local function findPivot(skin: Instance): (BasePart | Bone)?
	for _, d in skin:GetDescendants() do
		if d:IsA("Bone") then
			local n = string.lower(d.Name)
			if string.find(n, "hips") or string.find(n, "root") or string.find(n, "pelvis") then
				return d
			end
		end
	end

	local bone = skin:FindFirstChildWhichIsA("Bone", true)
	if bone then
		return bone
	end

	if skin:IsA("BasePart") then
		return skin
	elseif skin:IsA("Model") and skin.PrimaryPart then
		return skin.PrimaryPart
	end
	return skin:FindFirstChildWhichIsA("BasePart", true)
end

--- Orientasi pivot di ruang DUNIA.
--- Bone turunan Attachment: `Bone.CFrame` RELATIF PARENT, `WorldCFrame` yang
--- di ruang dunia. Mencampur keduanya menghasilkan sudut ngawur.
local function pivotWorldCFrame(pivot: BasePart | Bone): CFrame
	return if pivot:IsA("Bone") then pivot.WorldCFrame else pivot.CFrame
end

--- Apakah skin perlu diluruskan? Dipisah supaya bisa diputuskan SEBELUM weld
--- dibongkar (mesh yang masih ter-weld ke root anchored tidak bisa diputar —
--- weld langsung menariknya balik, jadi rotasi terlihat "tidak berefek").
local function needsAlign(skin: Instance, root: BasePart): boolean
	local pivot = findPivot(skin)
	if not pivot then
		return false
	end
	local dot = math.clamp(root.CFrame.LookVector:Dot(pivotWorldCFrame(pivot).LookVector), -1, 1)
	return math.deg(math.acos(dot)) > ALIGN_TOLERANCE_DEG
end

--- Luruskan arah hadap skin agar sama dengan rig, TANPA memindahkan posisinya.
--- Mengembalikan jumlah part yang diputar (0 bila sudah lurus / tak ada acuan).
---
--- Kenapa perlu: WeldConstraint membekukan offset relatif saat dibuat. Mesh
--- hasil import sering menghadap sumbu berbeda dari rig R15, dan selisih itu
--- ikut terkunci -> NPC berjalan maju tetapi badannya menyamping.
---
--- WAJIB dipanggil SETELAH weld skin<->rig dibongkar, kalau tidak rotasinya
--- tidak berefek (lihat catatan di needsAlign).
local function alignSkinToRig(skin: Instance, root: BasePart): number
	local pivot = findPivot(skin)
	if not pivot then
		return 0
	end

	local pivotWorld = pivotWorldCFrame(pivot)

	-- Sudah lurus? Jangan disentuh (hindari jitter presisi float).
	local dot = math.clamp(root.CFrame.LookVector:Dot(pivotWorld.LookVector), -1, 1)
	if math.deg(math.acos(dot)) <= ALIGN_TOLERANCE_DEG then
		return 0
	end

	-- Rotasi yang membawa orientasi pivot ke orientasi rig. Diterapkan sebagai
	-- delta DUNIA (dikali dari kiri) sehingga berlaku sama untuk semua part —
	-- termasuk saat pivot-nya bone yang tidak sejajar dengan mesh induknya.
	local delta = root.CFrame.Rotation * pivotWorld.Rotation:Inverse()

	local n = 0
	for _, part in collectParts(skin) do
		-- Putar di sekitar posisi part itu sendiri: posisi tetap, arah berubah.
		part.CFrame = CFrame.new(part.Position) * (delta * part.CFrame.Rotation)
		n += 1
	end
	return n
end

--- Sembunyikan seluruh part rig (kerangka tidak perlu terlihat kalau ada skin).
--- LocalTransparencyModifier tidak dipakai: itu client-only.
local function hideRig(rig: Model): number
	local n = 0
	for _, p in rig:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			p.Transparency = 1
			n += 1
		end
	end
	return n
end

--- Pasang skin ke rig. Aman dipanggil berulang (idempotent): weld yang
--- sudah ada tidak diduplikasi.
--- Mengembalikan ringkasan hasil untuk dilaporkan ke Output.
function SkinBinder:bind(rig: Model): { [string]: any }
	local result = {
		skins = 0,
		welded = 0,
		alreadyWelded = 0,
		collisionOff = 0,
		rigHidden = 0,
		animated = 0,
		aligned = 0,
		reWelded = 0,
		scriptsDisabled = {},
	}

	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		result.error = "rig tidak punya HumanoidRootPart"
		return result
	end

	local skins = self:findSkins(rig)
	result.skins = #skins
	if #skins == 0 then
		return result
	end

	local keepCollision = rig:GetAttribute("KeepSkinCollision") == true
	local keepOrientation = rig:GetAttribute("KeepSkinOrientation") == true

	for _, skin in skins do
		-- Script animasi lama yang bentrok
		for _, nm in disableConflictingScripts(skin) do
			table.insert(result.scriptsDisabled, skin.Name .. "/" .. nm)
		end

		-- Luruskan arah hadap skin ke rig. Posisi TIDAK diubah, hanya rotasi,
		-- dan hanya bila memang menyimpang.
		--
		-- URUTAN PENTING: cek dulu (needsAlign), bongkar weld, BARU putar.
		-- Mesh yang masih ter-weld ke root anchored tidak bisa diputar — weld
		-- langsung menariknya balik sehingga set CFrame tampak tidak berefek.
		if not keepOrientation and needsAlign(skin, root) then
			result.reWelded = removeSkinWelds(skin, root)
			result.aligned += alignSkinToRig(skin, root)
		end

		for _, part in collectParts(skin) do
			-- Weld ke root rig; skip bila pasangan part<->root sudah ter-weld.
			-- Weld bisa diparent di sisi mana pun, jadi cek keduanya.
			if isWeldedTo(part, root) then
				result.alreadyWelded += 1
			else
				local weld = Instance.new("WeldConstraint")
				weld.Name = "SkinWeld"
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = root
				result.welded += 1
			end

			-- Skin tidak boleh punya collision / massa: itu tugas rig.
			if not keepCollision then
				if part.CanCollide then
					part.CanCollide = false
					result.collisionOff += 1
				end
				part.Massless = true
			end
		end
	end

	-- Rig disembunyikan karena skin-lah yang tampil.
	-- HANYA saat game berjalan: kalau dilakukan di edit mode, Transparency = 1
	-- ikut TERSIMPAN ke file place dan rig jadi tak terlihat selamanya di
	-- Explorer/viewport. Di edit mode rig harus tetap tampak supaya bisa
	-- diposisikan dan di-skala.
	if RunService:IsRunning() and rig:GetAttribute("KeepRigVisible") ~= true then
		result.rigHidden = hideRig(rig)
	end

	-- Catat skin supaya raycast Line of Sight bisa mengabaikannya.
	-- Tanpa ini monster "melihat" badannya sendiri dan jadi buta.
	boundSkins[rig] = skins

	-- Animasi skin mengikuti AIState rig.
	-- Skin dianimasikan lewat AnimationController-nya sendiri, jadi
	-- AnimationManager (yang lewat Humanoid) tidak bisa menyentuhnya.
	for _, skin in skins do
		local animator = SkinAnimator.new(skin)
		if animator then
			animator:bindTo(rig)
			skinAnimators[skin] = animator
			result.animated += 1
		end
	end

	return result
end

--- Lepas animator skin milik sebuah rig (dipanggil saat monster dibersihkan).
function SkinBinder:unbind(rig: Model)
	for _, skin in boundSkins[rig] or {} do
		local animator = skinAnimators[skin]
		if animator then
			animator:destroy()
			skinAnimators[skin] = nil
		end
	end
	boundSkins[rig] = nil
end

return SkinBinder
