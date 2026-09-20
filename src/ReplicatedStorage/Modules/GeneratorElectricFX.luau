--!strict
--[[
	GeneratorElectricFX — EFEK VISUAL busur listrik pada generator (MODUL MANDIRI).

	Ini SUMBER sinyalnya: setiap kali efek muncul, modul ini men-fire sinyal
	"HighVoltage" di Model generator, dan GeneratorSFX memutar suaranya.
	Efek & suara jadi SATU sumber -> mustahil lepas sinkron.

	Perilaku:
	  - Selama generator nyala (Attribute "GeneratorPowered" = true), efek
	    menyala secara ACAK: tiap 3.5-9 detik muncul burst singkat (0.45s)
	    berisi kedip busur listrik + percikan + kilatan lampu.
	  - Generator mati -> efek berhenti & semua visual dipadamkan.
	  - Mode tahan: kalau Attribute "HighVoltageActive" (Bool) = true, efek
	    menyala TERUS (bukan burst) sampai attribute itu di-set false.
	    Berguna kalau tim mau efek listrik berdurasi panjang.

	Sinyal yang diterbitkan (dibaca GeneratorSFX):
	  BindableEvent "HighVoltage" di Model generator -> Fire() tiap burst.

	Yang dibuat modul ini (idempotent, semua di dalam folder
	Case.GeneratorElectricFX supaya rapi & gampang dihapus):
	  - 6 Attachment titik busur di permukaan Case
	  - 4 Beam busur listrik
	  - 1 ParticleEmitter percikan
	  - 1 PointLight kilatan

	Semua angka tuning ada di CONFIG di bawah. Nol konfigurasi di Studio.
]]

local CollectionService = game:GetService("CollectionService")

-- ======================================================================
-- CONFIG — ubah di sini saja
-- ======================================================================

local CONFIG = {
	-- Seberapa sering efek muncul sendiri (detik). Acak di antara dua angka ini.
	BurstMinInterval = 3.5,
	BurstMaxInterval = 9.0,
	-- Lama satu burst (detik).
	BurstDuration = 0.45,
	-- Frekuensi kedipan saat burst (Hz). 30 = halus, 12 = kedap-kedip kasar.
	FlickerHz = 30,

	-- Warna busur & lampu.
	Color = Color3.fromRGB(130, 220, 255),
	-- Terang kilatan lampu.
	LightBrightness = 6,
	LightRange = 26,
	-- Lebar busur (studs).
	BeamWidth = 0.09,
	-- Jumlah percikan per burst.
	SparkCount = 18,

	-- Titik busur: posisi di permukaan Case, skala -1..1 dari setengah ukuran.
	-- (dikali 0.92 supaya busurnya sedikit di dalam permukaan, tidak melayang)
	SurfaceInset = 0.92,
}

-- Sinyal yang sama dengan yang didengar GeneratorSFX.
local HV_EVENT_NAME = "HighVoltage"
local ATTR_POWERED = "GeneratorPowered"
local ATTR_HV_ACTIVE = "HighVoltageActive"
local FOLDER_NAME = "GeneratorElectricFX"

-- Titik sudut kotak (skala -1..1). Dipakai untuk menaruh attachment busur.
local CORNERS = {
	Vector3.new(1, 1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, -1, -1),
	Vector3.new(1, -1, -1),
}

-- Pasangan titik yang disambung busur (indeks ke CORNERS).
local ARC_PAIRS = {
	{ 1, 3 },
	{ 2, 4 },
	{ 5, 7 },
	{ 6, 8 },
}

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

-- ======================================================================
-- Modul
-- ======================================================================

local GeneratorElectricFX = {}

local state = {
	started = false,
	powered = false,
	active = false, -- burst / mode tahan sedang berjalan
	built = false,
}

local gen: Model? = nil
local casePart: BasePart? = nil
local beams: { Beam } = {}
local spark: ParticleEmitter? = nil
local flash: PointLight? = nil
local hvEvent: BindableEvent? = nil
local loopRunning = false

-- ----------------------------------------------------------------------
-- Membangun visual (idempotent)
-- ----------------------------------------------------------------------

local function build(): boolean
	if state.built then
		return true
	end
	local g = gen
	if not g then
		return false
	end

	local case = g:FindFirstChild("Case")
	if not case or not case:IsA("BasePart") then
		warn("[GeneratorElectricFX] 'Case' (BasePart) tidak ditemukan di generator; efek dilewati")
		return false
	end
	casePart = case

	-- Wadah rapi: Case.GeneratorElectricFX
	local folder = case:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = case
	end

	local half = case.Size * 0.5 * CONFIG.SurfaceInset

	-- Titik busur
	local points: { Attachment } = {}
	for i, corner in ipairs(CORNERS) do
		local name = "ArcPoint" .. i
		local att = folder:FindFirstChild(name)
		if not att then
			att = Instance.new("Attachment")
			att.Name = name
			att.Parent = folder
		end
		local a = att :: Attachment
		a.Position = Vector3.new(corner.X * half.X, corner.Y * half.Y, corner.Z * half.Z)
		table.insert(points, a)
	end

	-- Busur listrik
	beams = {}
	for i, pair in ipairs(ARC_PAIRS) do
		local name = "Arc" .. i
		local b = folder:FindFirstChild(name)
		if not b then
			b = Instance.new("Beam")
			b.Name = name
			b.Parent = folder
		end
		local beam = b :: Beam
		beam.Attachment0 = points[pair[1]]
		beam.Attachment1 = points[pair[2]]
		beam.FaceCamera = true
		beam.Width0 = CONFIG.BeamWidth
		beam.Width1 = CONFIG.BeamWidth
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(CONFIG.Color)
		beam.Enabled = false
		table.insert(beams, beam)
	end

	-- Percikan
	local sp = folder:FindFirstChild("Sparks")
	if not sp then
		sp = Instance.new("ParticleEmitter")
		sp.Name = "Sparks"
		sp.Parent = folder
	end
	local p = sp :: ParticleEmitter
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Color = ColorSequence.new(CONFIG.Color)
	p.LightEmission = 1
	p.LightInfluence = 0
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.Lifetime = NumberRange.new(0.18, 0.42)
	p.Speed = NumberRange.new(9, 20)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rate = 0
	p.Enabled = false
	spark = p

	-- Kilatan lampu
	local fl = folder:FindFirstChild("Flash")
	if not fl then
		fl = Instance.new("PointLight")
		fl.Name = "Flash"
		fl.Parent = folder
	end
	local light = fl :: PointLight
	light.Color = CONFIG.Color
	light.Brightness = 0
	light.Range = CONFIG.LightRange
	light.Enabled = false
	flash = light

	state.built = true
	return true
end

-- ----------------------------------------------------------------------
-- Visual on/off
-- ----------------------------------------------------------------------

-- Menyalakan visual dengan intensitas acak (bikin busurnya "hidup").
local function renderOn()
	for _, beam in ipairs(beams) do
		beam.Enabled = true
		local t = randRange(0.15, 0.85)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.5, t),
			NumberSequenceKeypoint.new(1, 0.75),
		})
		beam.CurveSize0 = randRange(-0.4, 0.4)
		beam.CurveSize1 = randRange(-0.4, 0.4)
	end
	if spark then
		spark.Enabled = true
	end
	if flash then
		flash.Enabled = true
		flash.Brightness = CONFIG.LightBrightness * randRange(0.5, 1.0)
	end
end

local function renderOff()
	for _, beam in ipairs(beams) do
		beam.Enabled = false
	end
	if spark then
		spark.Enabled = false
	end
	if flash then
		flash.Enabled = false
		flash.Brightness = 0
	end
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

-- Satu burst: kedip cepat, lalu padam. Sinyal di-fire SEKALI di awal
-- (satu efek = satu suara, tidak menumpuk).
local function burst()
	if state.active then
		return
	end
	state.active = true

	fireSignal()

	local step = 1 / math.max(1, CONFIG.FlickerHz)
	local elapsed = 0
	while elapsed < CONFIG.BurstDuration do
		if not state.powered then
			break
		end
		-- Kedip kasar: kadang terang, kadang hampir mati.
		if math.random() < 0.75 then
			renderOn()
		else
			renderOff()
		end
		if spark and math.random() < 0.5 then
			spark:Emit(math.random(2, math.max(2, CONFIG.SparkCount // 4)))
		end
		task.wait(step)
		elapsed += step
	end

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
	while state.powered do
		if gen and gen:GetAttribute(ATTR_HV_ACTIVE) ~= true then
			break
		end
		if math.random() < 0.8 then
			renderOn()
		else
			renderOff()
		end
		task.wait(1 / math.max(1, CONFIG.FlickerHz))
	end
	renderOff()
	state.active = false
end

-- Selama generator nyala: munculkan burst secara acak.
local function runLoop()
	if loopRunning then
		return
	end
	loopRunning = true
	while state.powered do
		-- Tunggu acak dulu.
		local waitFor = randRange(CONFIG.BurstMinInterval, CONFIG.BurstMaxInterval)
		local waited = 0
		while waited < waitFor and state.powered do
			task.wait(0.2)
			waited += 0.2
		end
		if not state.powered then
			break
		end

		if gen and gen:GetAttribute(ATTR_HV_ACTIVE) == true then
			holdOn() -- mode tahan: jalan terus sampai attribute false
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
-- Mengembalikan true kalau efek siap dipakai.
function GeneratorElectricFX.start(opts: { [string]: any }?): boolean
	opts = opts or {}
	if state.started then
		return state.built
	end
	state.started = true

	gen = opts.generator or findGenerator()
	if not gen then
		warn("[GeneratorElectricFX] Model generator tidak ditemukan; efek listrik dilewati")
		return false
	end

	-- Sinyal untuk GeneratorSFX. Dibuat kalau belum ada (idempotent: kalau
	-- GeneratorSFX sudah membuatnya, kita pakai yang sama).
	local ev = gen:FindFirstChild(HV_EVENT_NAME)
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = HV_EVENT_NAME
		ev.Parent = gen
	end
	hvEvent = ev :: BindableEvent

	if not build() then
		return false
	end

	-- Ikuti status generator. Sinyal perubahan SELALU disambung (dulu kalau
	-- generator sudah nyala saat start(), sambungan ini dilewati -> mematikan
	-- generator tidak pernah terbaca).
	local function applyPowered()
		local on = gen ~= nil and gen:GetAttribute(ATTR_POWERED) == true
		state.powered = on
		if on then
			if not loopRunning then
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

	return true
end

return GeneratorElectricFX
