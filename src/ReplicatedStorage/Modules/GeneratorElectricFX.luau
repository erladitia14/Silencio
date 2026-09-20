--!strict
--[[
	GeneratorElectricFX — PENGENDALI efek listrik generator (MODUL MANDIRI).

	Modul ini TIDAK membuat visual sendiri. Ia MENGENDALIKAN objek efek yang
	di-insert tim dari Toolbox, supaya efek & suara listrik selalu muncul
	BERSAMAAN.

	=== CARA PAKAI (nol script tambahan) ===
	1. Insert efek listrik dari Toolbox ke Workspace (bebas di mana saja).
	2. Beri TAG "GeneratorElectricFX" pada objek efek itu (View > Tag Editor).
	   Bisa Model, Folder, atau BasePart langsung.
	3. Selesai. Modul akan:
	     - memindahkan objek itu ke badan generator
	     - menyalakannya saat generator hidup (burst acak 3.5-9s)
	     - mematikannya saat generator mati
	     - men-fire sinyal "HighVoltage" (di ReplicatedStorage) tiap efek muncul
	       -> suara ikut

	KONTRAK: SEMUA ParticleEmitter / Beam / Trail / Light di dalam objek
	ber-tag itu DIKENDALIKAN modul (nyala saat burst, mati saat selesai).
	Kalau ada efek yang harus selalu nyala, taruh di luar objek ber-tag.

	Atribut opsional pada objek efek (boleh dipakai atau tidak):
	  EffectScale   (Number,  default 1)    : perbesar/perkecil efek (khusus Model)
	  EffectOffset  (Vector3, default 0)    : geser posisi dari titik tempel
	  FollowSurface (Bool,    default true) : tempel di badan generator

	=== SINYAL KE SUARA ===
	Setiap efek muncul -> BindableEvent "HighVoltage" di ReplicatedStorage di-fire.
	GeneratorSFX mendengarnya & memutar high_voltage_electricity.
	Jadi efek & suara SATU sumber, mustahil lepas sinkron.

	Syarat: generator harus sudah nyala (Attribute "GeneratorPowered" = true).
	Sinyal saat mesin belum hidup diabaikan.

	Mode tahan: Attribute "HighVoltageActive" (Bool) = true -> efek & suara
	jalan terus sampai di-set false (bukan burst acak).
]]

local CollectionService = game:GetService("CollectionService")

-- ======================================================================
-- CONFIG — ubah di sini saja
-- ======================================================================

local CONFIG = {
	-- TAG objek efek (opsional). Kalau tidak ada tag, modul otomatis memakai
	-- ParticleEmitter yang jadi ANAK LANGSUNG Case (lihat AutoDetectInCase).
	EffectTag = "GeneratorElectricFX",

	-- Kalau true dan tidak ada objek ber-tag, modul memakai ParticleEmitter
	-- yang berada langsung di dalam Case. Berguna kalau tim menempelkan efek
	-- tanpa Attachment (lebih rapi di Explorer).
	AutoDetectInCase = true,

	-- Munculkan burst PERTAMA segera saat generator nyala (detik). Ini momen
	-- paling penting: pemain baru menekan tombol power dan harus langsung
	-- lihat & dengar efeknya. Tanpa ini pemain menunggu 3.5-9 detik tanpa apa-apa.
	FirstBurstDelay = 0.15,

	-- Seberapa sering efek muncul lagi setelahnya (detik). Acak di antara dua angka.
	BurstMinInterval = 3.5,
	BurstMaxInterval = 9.0,
	-- Lama satu burst (detik). Dinaikkan dari 0.45 supaya efeknya sempat terlihat.
	BurstDuration = 0.9,

	-- Pindahkan objek efek ke badan generator? DEFAULT FALSE = JANGAN sentuh.
	-- Kalau true, modul akan memindahkan objek ke Anchor di bawah — dan itu
	-- MENIMPA penempatan manual tim (pernah bikin bingung: attachment sudah
	-- dipindah ke tengah, tapi balik lagi ke depan). Biarkan false kecuali
	-- memang mau modul yang mengatur posisi.
	MoveToAnchor = false,

	-- Titik tempel (dipakai HANYA kalau MoveToAnchor = true). Skala -1..1
	-- terhadap setengah ukuran Case. PENTING: minimal satu komponen harus
	-- > 1.0 supaya keluar dari permukaan mesh (nilai < 1.0 = DI DALAM badan
	-- generator, tidak kelihatan).
	Anchor = Vector3.new(0, 0.55, 1.15),

	-- Perbesar partikel efek saat game jalan. Aset Toolbox punya partikel sangat
	-- tipis (Lifetime 0.1s, Speed 0.2, Size maks 0.82) sehingga praktis tidak
	-- terlihat. Nilai di bawah ini mengalikan properti aset; 1 = jangan diubah.
	SizeMultiplier = 2.5,      -- ukuran partikel
	LifetimeMultiplier = 3.0,  -- umur partikel (0.1s -> 0.3s)
	SpeedMultiplier = 4.0,     -- kecepatan sebar (0.2 -> 0.8)
	RateMultiplier = 1.0,      -- partikel per detik per emitter

	-- SEBARAN EFEK: emitter dikloning ke titik-titik ini supaya listriknya
	-- keluar dari BANYAK tempat, bukan satu titik saja. Skala -1..1 terhadap
	-- setengah ukuran Case.
	-- ATURAN: minimal SATU komponen harus > 1.0 (keluar permukaan mesh).
	-- Kosongkan (={}) kalau mau satu titik saja.
	SpreadPoints = {
		Vector3.new(-0.70, -0.50, 1.15), -- depan bawah kiri
		Vector3.new(0.70, -0.50, 1.15),  -- depan bawah kanan
		Vector3.new(-0.70, 0.50, 1.15),  -- depan atas kiri
		Vector3.new(0.70, 0.50, 1.15),   -- depan atas kanan
		Vector3.new(1.15, 0.30, 0),      -- samping kanan
		Vector3.new(-1.15, 0.30, 0),     -- samping kiri
		Vector3.new(1.15, -0.40, 0),     -- samping kanan bawah
		Vector3.new(-1.15, -0.40, 0),    -- samping kiri bawah
	},
}

local ATTR_POWERED = "GeneratorPowered"
local ATTR_HV_ACTIVE = "HighVoltageActive"
local HV_EVENT_NAME = "HighVoltage"

-- Attachment internal buatan modul, tempat kloningan emitter sebaran ditaruh.
-- Dinamai jelas supaya tim tahu ini bukan ditempel manual.
local SPREAD_HOLDER = "GeneratorElectricFX_Points"

-- ======================================================================
-- Util
-- ======================================================================

-- Model generator dalam: dari tag "AssemblySlot" naik ke ancestor bernama
-- "Generator". Pola sama dengan BatteryPuzzleController & GeneratorSFX.
local function findGenerator(): Model?
	for _, slot in ipairs(CollectionService:GetTagged("AssemblySlot")) do
		local anc = slot:FindFirstAncestorOfClass("Model")
		while anc ~= nil do
			if anc.Name == "Generator" then
				return anc
			end
			anc = anc:FindFirstAncestorOfClass("Model")
		end
	end
	return nil
end

local function randRange(a: number, b: number): number
	if b < a then
		a, b = b, a
	end
	return a + math.random() * (b - a)
end

local function readNumber(obj: Instance, name: string, default: number): number
	local ok, val = pcall(function()
		return obj:GetAttribute(name)
	end)
	if ok and type(val) == "number" and val > 0 then
		return val
	end
	return default
end

local function readVector(obj: Instance, name: string, default: Vector3): Vector3
	local ok, val = pcall(function()
		return obj:GetAttribute(name)
	end)
	if ok and typeof(val) == "Vector3" then
		return val
	end
	return default
end

local function readBool(obj: Instance, name: string, default: boolean): boolean
	local ok, val = pcall(function()
		return obj:GetAttribute(name)
	end)
	if ok and type(val) == "boolean" then
		return val
	end
	return default
end

-- Sinyal efek listrik -> suara. Ditaruh di ReplicatedStorage (bukan di dalam
-- Model generator) supaya tidak mengotori scene generator. Dibuat kalau belum
-- ada; kalau sudah ada (dibuat GeneratorSFX), dipakai yang sama.
local function getHVEvent(): BindableEvent
	local rs = game:GetService("ReplicatedStorage")
	local ev = rs:FindFirstChild(HV_EVENT_NAME)
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = HV_EVENT_NAME
		ev.Parent = rs
	end
	return ev :: BindableEvent
end

-- ======================================================================
-- Modul
-- ======================================================================

local GeneratorElectricFX = {}

local state = {
	started = false,
	powered = false,
	active = false,
	adopted = false,
}

local gen: Model? = nil
local effectObj: Instance? = nil
local hvEvent: BindableEvent? = nil
local loopRunning = false

-- Semua objek yang bisa "menyala" di dalam efek yang diadopsi.
local emitters: { Instance } = {}

-- ----------------------------------------------------------------------
-- Mengumpulkan efek
-- ----------------------------------------------------------------------

-- Kumpulkan semua objek yang bisa "menyala" dari sebuah instance + turunannya.
local function collectInto(list: { Instance }, root: Instance)
	local function consider(d: Instance)
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
			or d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")
			or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("Smoke") then
			table.insert(list, d)
		end
	end

	consider(root)
	for _, d in ipairs(root:GetDescendants()) do
		consider(d)
	end
end

-- Perbesar partikel aset Toolbox yang terlalu tipis. Tanpa ini efeknya ADA tapi
-- praktis tidak terlihat (aset Electric Particle: Lifetime 0.1s, Speed 0.2,
-- Size maks 0.82 studs). Dikalikan dari nilai aset, jadi aset lain tetap aman.
local function tuneEmitter(e: Instance)
	if not e:IsA("ParticleEmitter") then
		return
	end
	local pe = e :: ParticleEmitter

	-- Size: kalikan setiap keypoint
	local sz = pe.Size
	local newKeys = {}
	for _, kp in ipairs(sz.Keypoints) do
		table.insert(newKeys, NumberSequenceKeypoint.new(kp.Time, kp.Value * CONFIG.SizeMultiplier))
	end
	pe.Size = NumberSequence.new(newKeys)

	-- Lifetime
	pe.Lifetime = NumberRange.new(
		pe.Lifetime.Min * CONFIG.LifetimeMultiplier,
		pe.Lifetime.Max * CONFIG.LifetimeMultiplier)

	-- Speed
	pe.Speed = NumberRange.new(
		pe.Speed.Min * CONFIG.SpeedMultiplier,
		pe.Speed.Max * CONFIG.SpeedMultiplier)

	-- Rate
	pe.Rate = pe.Rate * CONFIG.RateMultiplier
end

-- ----------------------------------------------------------------------
-- Nyalakan / matikan efek
-- (didefinisikan SEBELUM adopt() — fungsi lokal wajib ada sebelum dipakai)
-- ----------------------------------------------------------------------

local function renderOn()
	if not effectObj then
		return
	end
	for _, e in ipairs(emitters) do
		(e :: any).Enabled = true
	end
end

local function renderOff()
	for _, e in ipairs(emitters) do
		(e :: any).Enabled = false
	end
end

-- Sebarkan efek ke banyak titik di badan generator. Emitter SUMBER tetap di
-- tempatnya (tidak digeser); kloningannya ditaruh di titik-titik CONFIG.SpreadPoints.
-- Semua kloningan dimasukkan ke daftar emitters supaya ikut nyala/mati bareng burst.
--
-- Kenapa dikloning, bukan digeser: satu emitter hanya punya satu posisi.
-- Kloning bikin efeknya benar-benar MENYEBAR dari banyak tempat sekaligus.
local function spreadEffects(case: BasePart)
	if #CONFIG.SpreadPoints == 0 then
		return
	end

	-- Ambil emitter SUMBER (yang asli) sebagai cetakan.
	local sources: { Instance } = {}
	for _, e in ipairs(emitters) do
		if e:IsA("ParticleEmitter") then
			table.insert(sources, e)
		end
	end
	if #sources == 0 then
		return
	end

	local half = case.Size * 0.5

	-- Wadah kloningan: Attachment internal, dinamai jelas supaya tim tahu ini
	-- buatan modul (bukan ditempel manual). Ditaruh di dalam Case.
	local holder = case:FindFirstChild(SPREAD_HOLDER)
	if not holder then
		holder = Instance.new("Attachment")
		holder.Name = SPREAD_HOLDER
		holder.Parent = case
	end

	for i, pt in ipairs(CONFIG.SpreadPoints) do
		-- Titik HARUS keluar dari permukaan mesh (lihat catatan CONFIG).
		local localPos = Vector3.new(pt.X * half.X, pt.Y * half.Y, pt.Z * half.Z)

		local attName = "Point" .. i
		local att = (holder :: Attachment):FindFirstChild(attName)
		if not att then
			att = Instance.new("Attachment")
			att.Name = attName
			att.Parent = holder
		end
		local a = att :: Attachment
		-- Set Parent dulu, baru WorldCFrame (kalau tidak, dianggap lokal).
		a.WorldCFrame = case.CFrame * CFrame.new(localPos)

		for _, src in ipairs(sources) do
			local cloneName = src.Name .. "_s" .. i
			local existing = a:FindFirstChild(cloneName)
			if existing then
				existing:Destroy()
			end
			local c = src:Clone()
			c.Name = cloneName
			c.Enabled = false
			c.Parent = a
			table.insert(emitters, c)
		end
	end
end

-- ----------------------------------------------------------------------
-- Adopsi: pindahkan efek ber-tag ke badan generator
-- ----------------------------------------------------------------------

local function adopt(): boolean
	if state.adopted then
		return effectObj ~= nil
	end
	local g = gen
	if not g then
		return false
	end

	local case = g:FindFirstChild("Case")
	if not case or not case:IsA("BasePart") then
		warn("[GeneratorElectricFX] 'Case' (BasePart) tidak ditemukan di generator")
		return false
	end

	-- Cari objek efek: (1) yang ber-tag, (2) kalau tidak ada, emitter yang
	-- jadi ANAK LANGSUNG Case (tim menempelkan efek tanpa Attachment).
	local obj: Instance? = nil
	local tagged = CollectionService:GetTagged(CONFIG.EffectTag)
	if #tagged > 0 then
		obj = tagged[1]
	elseif CONFIG.AutoDetectInCase then
		for _, c in ipairs(case:GetChildren()) do
			if c:IsA("ParticleEmitter") or c:IsA("Beam") or c:IsA("Trail")
				or c:IsA("PointLight") or c:IsA("SpotLight") then
				obj = c
				break
			end
		end
	end

	if not obj then
		warn("[GeneratorElectricFX] Tidak ada efek: tidak ada objek ber-tag '"
			.. CONFIG.EffectTag .. "' dan tidak ada ParticleEmitter langsung di dalam Case")
		return false
	end

	-- PENTING: JANGAN memindahkan objek efek. Tim yang mengatur posisinya.
	-- Dulu modul SELALU memindahkan ke CONFIG.Anchor, sehingga penempatan
	-- manual (mis. attachment sudah dipindah ke tengah) selalu ditimpa dan
	-- efeknya balik lagi ke tempat lama. Sekarang hanya dipindah kalau
	-- CONFIG.MoveToAnchor = true.
	if CONFIG.MoveToAnchor then
		local scale = readNumber(obj, "EffectScale", 1)
		local offset = readVector(obj, "EffectOffset", Vector3.zero)
		local follow = readBool(obj, "FollowSurface", true)

		local anchor = Vector3.zero
		if follow then
			anchor = Vector3.new(
				CONFIG.Anchor.X * case.Size.X * 0.5,
				CONFIG.Anchor.Y * case.Size.Y * 0.5,
				CONFIG.Anchor.Z * case.Size.Z * 0.5)
		end
		anchor += offset

		-- Pakai CFrame, bukan Vector3 sumbu dunia: Case bisa diputar.
		local targetCF = case.CFrame * CFrame.new(anchor)

		if obj:IsA("BasePart") then
			obj.CFrame = targetCF
		elseif obj:IsA("Model") then
			(obj :: Model):PivotTo(targetCF)
			if scale ~= 1 then
				(obj :: Model):ScaleTo(scale)
			end
		elseif obj:IsA("Attachment") then
			(obj :: Attachment).WorldCFrame = targetCF
		end
	end

	-- Jangan biarkan efek menghalangi / menabrak pemain.
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end

	effectObj = obj
	state.adopted = true

	-- Kumpulkan SEMUA efek di dalam Case, bukan cuma objek pertama yang ketemu.
	-- Aset Toolbox sering menaruh beberapa emitter bersaudara (mis. 4 identik);
	-- kalau cuma satu yang diambil, sebarannya cuma mengkloning satu.
	emitters = {}
	collectInto(emitters, obj)
	for _, c in ipairs(case:GetChildren()) do
		collectInto(emitters, c)
	end

	-- Buang duplikat (emitter bisa terkumpul dua kali dari loop di atas).
	local seen: { [Instance]: boolean } = {}
	local unique: { Instance } = {}
	for _, e in ipairs(emitters) do
		if not seen[e] then
			seen[e] = true
			table.insert(unique, e)
		end
	end
	emitters = unique

	-- Perbesar partikel aset yang terlalu tipis (lihat tuneEmitter).
	for _, e in ipairs(emitters) do
		tuneEmitter(e)
	end

	-- SEBARKAN efek ke beberapa titik di badan generator. Tanpa ini efeknya
	-- cuma menumpuk di satu titik (keluhan Aer: "kenapa cuman disini doang").
	spreadEffects(case)

	-- PENTING: matikan efek SEKARANG saat adopsi. Aset Toolbox biasanya
	-- datang dengan Enabled=true, jadi kalau tidak dimatikan di sini efeknya
	-- sudah menyala sebelum generator hidup.
	renderOff()

	if #emitters == 0 then
		warn("[GeneratorElectricFX] Objek efek tidak punya ParticleEmitter/Beam/Light/Trail. "
			.. "Efeknya tidak akan kelihatan.")
	end

	return true
end

-- ----------------------------------------------------------------------
-- Sinyal + burst
-- ----------------------------------------------------------------------

-- Memberi tahu GeneratorSFX supaya suaranya berbunyi BERSAMAAN dengan efek.
local function fireSignal()
	local ev = hvEvent
	if ev then
		ev:Fire()
	end
end

-- Satu burst: efek nyala sebentar, lalu padam. Sinyal di-fire SEKALI di awal
-- (satu efek = satu suara, tidak menumpuk).
local function burst()
	if state.active then
		return
	end
	state.active = true

	fireSignal()
	renderOn()
	task.wait(CONFIG.BurstDuration)
	renderOff()

	state.active = false
end

-- Mode tahan: efek menyala terus sampai attribute HighVoltageActive = false.
local function holdOn()
	if state.active then
		return
	end
	state.active = true
	fireSignal()
	renderOn()
	while state.powered do
		if gen and gen:GetAttribute(ATTR_HV_ACTIVE) ~= true then
			break
		end
		task.wait(0.2)
	end
	renderOff()
	state.active = false
end

-- Selama generator nyala: burst PERTAMA langsung, lalu acak.
local function runLoop()
	if loopRunning then
		return
	end
	loopRunning = true

	-- Burst pertama segera: pemain baru menekan tombol power dan harus langsung
	-- lihat & dengar efeknya (tanpa ini mereka menunggu 3.5-9 detik tanpa apa-apa).
	local waited = 0
	while waited < CONFIG.FirstBurstDelay and state.powered do
		task.wait(0.05)
		waited += 0.05
	end
	if state.powered then
		if gen and gen:GetAttribute(ATTR_HV_ACTIVE) == true then
			holdOn()
		else
			burst()
		end
	end

	while state.powered do
		local waitFor = randRange(CONFIG.BurstMinInterval, CONFIG.BurstMaxInterval)
		local waited2 = 0
		while waited2 < waitFor and state.powered do
			task.wait(0.2)
			waited2 += 0.2
		end
		if not state.powered then
			break
		end

		if gen and gen:GetAttribute(ATTR_HV_ACTIVE) == true then
			holdOn()
		else
			burst()
		end
	end
	renderOff()
	loopRunning = false
end

-- ----------------------------------------------------------------------
-- API
-- ----------------------------------------------------------------------

-- opts (opsional; kosong = cari otomatis dari scene):
--   generator : Model  (Model generator dalam)
-- Mengembalikan true kalau generator + efek ketemu & siap.
function GeneratorElectricFX.start(opts: { [string]: any }?): boolean
	opts = opts or {}
	if state.started then
		return state.adopted
	end
	state.started = true

	gen = opts.generator or findGenerator()
	if not gen then
		warn("[GeneratorElectricFX] Model generator tidak ditemukan; efek listrik dilewati")
		return false
	end

	-- Sinyal untuk GeneratorSFX. Ditaruh di ReplicatedStorage (bukan di Model
	-- generator) sesuai permintaan Aer. Idempotent: kalau sudah ada, dipakai.
	hvEvent = getHVEvent()

	local ok = adopt()

	-- Ikuti status generator. Sinyal perubahan SELALU disambung (kalau tidak,
	-- mematikan generator saat efek sudah jalan tidak pernah terbaca).
	local function applyPowered()
		local on = gen ~= nil and gen:GetAttribute(ATTR_POWERED) == true
		state.powered = on
		if on then
			if not loopRunning and state.adopted then
				task.spawn(runLoop)
			end
		else
			renderOff()
		end
	end

	gen:GetAttributeChangedSignal(ATTR_POWERED):Connect(applyPowered)
	if gen:GetAttribute(ATTR_POWERED) == true then
		applyPowered()
	end

	-- Mode tahan diminta sebelum generator nyala -> diterapkan saat nyala.
	gen:GetAttributeChangedSignal(ATTR_HV_ACTIVE):Connect(function()
		if gen and gen:GetAttribute(ATTR_HV_ACTIVE) == true and state.powered and not state.active then
			task.spawn(holdOn)
		end
	end)

	-- Kalau efek di-insert SETELAH game jalan: adopsi begitu tag muncul.
	CollectionService:GetInstanceAddedSignal(CONFIG.EffectTag):Connect(function(_inst)
		if state.adopted then
			return
		end
		if adopt() then
			if state.powered and not loopRunning then
				task.spawn(runLoop)
			end
		end
	end)

	return ok
end

return GeneratorElectricFX
