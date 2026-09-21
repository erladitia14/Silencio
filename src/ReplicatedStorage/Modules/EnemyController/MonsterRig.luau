--!strict
--[[
	MonsterRig.luau
	---------------
	Menyiapkan monster jadi RIG YANG BISA BERJALAN & MELANGKAH dengan benar.

	MASALAH YANG DISELESAIKAN
	-------------------------
	Kalau mesh monster (badut) dijadikan HumanoidRootPart APA ADANYA, kotak
	collision-nya sebesar mesh (mis. 6.1 x 7.4 x 1.6 stud) dan bagian bawahnya
	menyeret tanah. Akibatnya monster TIDAK PUNYA RUANG untuk "melangkah":
	gundukan/undakan sekecil apa pun membuatnya MENTOK (stuck), walau
	AutoJumpEnabled sudah true.

	Bandingkan karakter Roblox normal: HumanoidRootPart-nya KECIL (2x2x1) dan
	MELAYANG ~2 stud di atas tanah, kaki part terpisah -> bisa melangkahi
	gundukan rendah tanpa lompat.

	SOLUSI (di sini)
	----------------
	Bikin HumanoidRootPart PROXY: Part kecil, tak terlihat, melayang sesuai
	HipHeight. Mesh monster jadi MESH VISUAL (CanCollide=false) yang di-weld ke
	proxy. Jadi:
	  - collision = kotak kecil ramping -> bisa melangkah, tidak nyangkut
	  - mesh tetap tampil penuh & tetap beranimasi (bone tetap di dalam model)
	  - mesh tidak menembus tembok karena proxy tetap punya collision

	CATATAN: mesh TIDAK dipindah/diputar oleh modul ini. Kalau orientasi mesh
	nyamping, itu sifat asetnya -> pakai Attribute "MeshYawOffset" (derajat).

	CARA PAKAI: cukup tag "Monster" pada Model. Nol konfigurasi.

	ATTRIBUTE (semua OPSIONAL, di Model monster):
	  ColliderSize    (Vector3) -> ukuran kotak collision proxy. Default 3,5,3.
	  ColliderOffset  (Vector3) -> geser proxy dari posisi mesh. Default 0,0,0.
	  MeshYawOffset   (number)  -> putar MESH visual (derajat) untuk membetulkan
	                               arah hadap aset yang nyamping. Default 0.
	  MeshYawOffsetX/Z(number)  -> kalau perlu koreksi pitch/roll juga.
	  KeepCollision   (Bool)    -> true = jangan sentuh collision sama sekali
	                               (modul tidak bikin proxy).
	  NoProxy         (Bool)    -> true = jangan bikin proxy (mesh tetap HRP).
	  HipHeight       (number)  -> paksa HipHeight proxy (default: 60% tinggi mesh).

	MODUL INI IDEMPOTENT: dipanggil dua kali tidak bikin proxy/weld ganda.
]]

local MonsterRig = {}

--- Script animasi bawaan yang sering berebut Animator dengan AnimationManager.
local CONFLICTING_SCRIPTS = { Anim = true, Animate = true }

--- Nama yang dipakai untuk part proxy & weld.
local PROXY_NAME = "HumanoidRootPart"
local WELD_NAME = "MonsterRigWeld"

--- Nama asli mesh disimpan di Attribute supaya bisa dibalik/di-debug.
local ATTR_MESH_NAME = "MonsterRig_MeshName"

---------------------------------------------------------------------
-- Util
---------------------------------------------------------------------

--- Ambil Attribute Vector3 dengan default (aman kalau salah tipe).
local function vecAttr(model: Instance, name: string, default: Vector3): Vector3
	local v = model:GetAttribute(name)
	if typeof(v) == "Vector3" then
		return v
	end
	return default
end

--- Ambil Attribute number dengan default.
local function numAttr(model: Instance, name: string, default: number): number
	local v = model:GetAttribute(name)
	if typeof(v) == "number" then
		return v
	end
	return default
end

--- Bounding box GEOMETRI RENDER model (mengikuti bentuk mesh, bukan Size part).
--- Mengembalikan (center, size) atau nil.
local function renderBounds(model: Model): (Vector3?, Vector3?)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not cf or not size then
		return nil, nil
	end
	return cf.Position, size
end

--- Y TERENDAH dari GEOMETRI NYATA mesh (world space).
---
--- Urutan sumber (yang paling dipercaya dulu):
---   1. BONE  -> mesh skinned: bone yang menggerakkan mesh, jadi posisinya
---      yang benar-benar menentukan di mana kaki berada.
---   2. BasePart anak -> mesh biasa tanpa bone.
---   3. Bounding box render -> jaring pengaman terakhir.
---
--- KENAPA BUKAN `part.Size.Y`: kotak part hasil import sering TIDAK sejalan
--- dengan mesh visualnya. Contoh nyata di proyek ini: `Size.Y = 7.37` tapi
--- kaki sebenarnya cuma 3.52 dari pusat -> selisih 0.16 stud bikin monster
--- ngambang saat Humanoid memakai angka itu sebagai HipHeight.
local function lowestPointY(mesh: BasePart, model: Model): number?
	local lo = math.huge

	-- 1. Bone (paling akurat untuk mesh skinned).
	for _, d in ipairs(mesh:GetDescendants()) do
		if d:IsA("Bone") then
			local y = d.WorldPosition.Y
			if y < lo then
				lo = y
			end
		end
	end
	if lo < math.huge then
		return lo
	end

	-- 2. BasePart lain di dalam mesh (mesh biasa).
	for _, d in ipairs(mesh:GetDescendants()) do
		if d:IsA("BasePart") then
			local y = d.Position.Y - d.Size.Y * 0.5
			if y < lo then
				lo = y
			end
		end
	end
	if lo < math.huge then
		return lo
	end

	-- 3. Jaring pengaman: bounding box render.
	local _, size = renderBounds(model)
	if size then
		local center = mesh.Position.Y
		return center - size.Y * 0.5
	end

	return nil
end

--- Cari part mesh utama: part pertama yang punya Bone (mesh skinned), kalau
--- tidak ada ambil BasePart pertama. Mengembalikan nil bila model tanpa part.
local function findMeshPart(model: Model): BasePart?
	local firstPart: BasePart? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if not firstPart then
				firstPart = d
			end
			-- MeshPart yang punya Bone = mesh visual utama
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("Bone") then
					return d
				end
			end
		end
	end
	return firstPart
end

--- Matikan LocalScript "Animate"/"Anim" bawaan di dalam model.
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

--- Pastikan Humanoid punya Animator, dan buang AnimationController bentrok.
local function fixAnimator(model: Model, humanoid: Humanoid): boolean
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

--- Nyalakan collision semua BasePart model.
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

--- Apakah model sudah punya proxy (dipanggil ulang)?
local function findExistingProxy(model: Model): (BasePart?, BasePart?)
	-- Proxy = part bernama HumanoidRootPart yang BUKAN mesh (punya weld ke mesh)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name == PROXY_NAME then
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("WeldConstraint") and c.Name == WELD_NAME then
					return d, (c.Part1 :: BasePart?)
				end
			end
		end
	end
	return nil, nil
end

---------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------

--- Siapkan monster. Idempotent.
--- Mengembalikan ringkasan untuk log.
function MonsterRig:setup(model: Model): { [string]: any }
	local result = {
		scriptsDisabled = {},
		animControllerRemoved = false,
		proxyCreated = false,
		proxyName = nil :: string?,
		meshName = nil :: string?,
		hipHeight = nil :: number?,
		colliderSize = nil :: Vector3?,
		collisionOn = 0,
		rotatedMesh = 0,
	}

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		result.error = "model tidak punya Humanoid"
		return result
	end

	-- 1. Matikan script animasi bentrok (sebelum Animator diambil alih).
	result.scriptsDisabled = disableConflictingScripts(model)

	-- 2. Satu penyetir animasi: Humanoid.Animator.
	result.animControllerRemoved = fixAnimator(model, humanoid)

	-- 3. PROXY: collision ramping + mesh jadi visual.
	--
	-- Dilewati kalau tim minta atur sendiri.
	local skipProxy = (model:GetAttribute("NoProxy") == true)
		or (model:GetAttribute("KeepCollision") == true)

	if not skipProxy then
		local existingProxy, existingMesh = findExistingProxy(model)
		local mesh: BasePart?
		local proxy: BasePart?

		if existingProxy and existingMesh then
			-- Sudah pernah di-setup -> idempotent, pakai yang ada.
			proxy = existingProxy
			mesh = existingMesh
			result.proxyCreated = false
		else
			mesh = findMeshPart(model)
			if not mesh then
				result.error = "model tidak punya BasePart (mesh)"
				return result
			end

			-- Simpan nama asli mesh (biar bisa dibalikin / jelas di Explorer).
			if mesh:GetAttribute(ATTR_MESH_NAME) == nil then
				mesh:SetAttribute(ATTR_MESH_NAME, mesh.Name)
			end
			local originalMeshName = mesh:GetAttribute(ATTR_MESH_NAME) :: string

			-- Ukuran collider: default 3 x (60% tinggi render) x 3, tapi jangan
			-- lebih pendek dari 3 stud supaya tetap stabil.
			local _, renderSize = renderBounds(model)
			local defaultH = 5
			if renderSize then
				defaultH = math.clamp(renderSize.Y * 0.6, 3, 12)
			end
			local colSize = vecAttr(model, "ColliderSize", Vector3.new(3, defaultH, 3))
			local colOffset = vecAttr(model, "ColliderOffset", Vector3.zero)

			-- Titik acuan: pakai CFrame mesh (mesh = penentu posisi/rotasi awal).
			local baseCF = mesh.CFrame * CFrame.new(colOffset)

			-- Nama mesh diganti supaya nama "HumanoidRootPart" bebas dipakai proxy.
			mesh.Name = "Mesh"

			proxy = Instance.new("Part")
			proxy.Name = PROXY_NAME
			proxy.Size = colSize
			proxy.Transparency = 1
			proxy.CanCollide = true
			proxy.Anchored = false
			proxy.Massless = true
			proxy.CFrame = baseCF
			proxy.Parent = model

			-- Mesh jadi visual: tidak menahan gerak, tidak punya massa.
			mesh.CanCollide = false
			mesh.Massless = true

			-- Weld mesh ke proxy (mesh ikut gerak proxy).
			local weld = Instance.new("WeldConstraint")
			weld.Name = WELD_NAME
			weld.Part0 = proxy
			weld.Part1 = mesh
			weld.Parent = proxy

			model.PrimaryPart = proxy
			task.wait(0.1)

			result.proxyCreated = true
			result.meshName = originalMeshName
			result.colliderSize = colSize
		end

		result.proxyName = proxy and proxy.Name or nil

		-- Humanoid harus menganggap PROXY sebagai root.
		if proxy and humanoid.RootPart ~= proxy then
			model.PrimaryPart = proxy
			task.wait(0.05)
		end

		-- ROTASI MESH (untuk aset yang "depan"-nya nyamping). Mesh DIPUTAR
		-- mengelilingi posisinya sendiri; posisi TIDAK berubah.
		--
		-- PENTING: dilakukan SEBELUM hitung HipHeight, karena memutar mesh
		-- mengubah di mana kaki berada.
		local yaw = numAttr(model, "MeshYawOffset", 0)
		local pitch = numAttr(model, "MeshYawOffsetX", 0)
		local roll = numAttr(model, "MeshYawOffsetZ", 0)
		if mesh and proxy and (yaw ~= 0 or pitch ~= 0 or roll ~= 0) then
			local rot = CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
			-- Weld membekukan offset, jadi bongkar dulu -> putar -> weld ulang.
			for _, c in ipairs(proxy:GetChildren()) do
				if c:IsA("WeldConstraint") and c.Name == WELD_NAME then
					c:Destroy()
				end
			end
			mesh.CFrame = CFrame.new(mesh.Position) * (rot * mesh.CFrame.Rotation)
			local weld = Instance.new("WeldConstraint")
			weld.Name = WELD_NAME
			weld.Part0 = proxy
			weld.Part1 = mesh
			weld.Parent = proxy
			task.wait(0.05)
			result.rotatedMesh = 1
		end

		-- HipHeight: taruh proxy pada ketinggian yang membuat KAKI MESH napak.
		--
		-- SEMANTIK YANG BENAR (dibuktikan empiris pada rig R15 bawaan Roblox:
		-- HipHeight 2.1924 == (pusat HRP -> kaki) 3.1924 - (HRP.Size.Y/2) 1.0):
		--     HipHeight = jarak dari BAWAH HumanoidRootPart ke lantai
		-- BUKAN dari pusat RootPart. Selisihnya = setengah tinggi proxy.
		--
		-- Jadi:
		--     HipHeight = (pusat proxy -> titik terendah mesh) - proxy.Size.Y/2
		--
		-- Dan JANGAN pakai mesh.Size.Y/2 untuk "titik terendah": kotak part hasil
		-- import sering tidak sejalan dengan mesh visualnya (kasus nyata di proyek
		-- ini: Size.Y = 7.37 padahal kaki sebenarnya cuma 3.52 dari pusat). Ukur
		-- dari GEOMETRI NYATA: titik terendah BONE (mesh skinned).
		if mesh and proxy and model:GetAttribute("KeepHipHeight") ~= true then
			local override = model:GetAttribute("HipHeight")
			if typeof(override) == "number" then
				humanoid.HipHeight = override
			else
				local lowest = lowestPointY(mesh, model)
				local footDistance
				if lowest then
					footDistance = proxy.Position.Y - lowest
				else
					-- Jaring pengaman: tidak ada bone/part -> pakai kotak part.
					footDistance = mesh.Size.Y * 0.5
				end
				-- HipHeightOffset: koreksi halus dari tim (stud). Positif = naikkan
				-- monster, negatif = turunkan. Untuk mesh yang geometri render-nya
				-- sedikit meleset dari bone (kasus nyata: 0.16 stud).
				local offset = numAttr(model, "HipHeightOffset", 0)
				humanoid.HipHeight = math.max(0, footDistance - proxy.Size.Y * 0.5 + offset)
			end
			result.hipHeight = humanoid.HipHeight
		end
	else
		-- Tidak bikin proxy: perilaku lama (mesh jadi collision).
		if model:GetAttribute("KeepCollision") ~= true then
			result.collisionOn = enableCollision(model)
		end
	end

	return result
end

return MonsterRig
