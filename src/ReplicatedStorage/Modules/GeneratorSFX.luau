--!strict
--[[
	GeneratorSFX — pendengar suara generator (MODUL MANDIRI).

	Prinsip: modul ini TIDAK mengubah sistem apa pun. Ia hanya MENDENGARKAN
	kejadian yang sudah diterbitkan sistem lain, lalu memainkan Sound yang
	sudah disiapkan tim di dalam Attachment "GeneratorSFX".

	Hook yang dipakai (semuanya sudah ada, nol perubahan di sistem lain):
	  prompt "GeneratorActivatePrompt"  (dibuat ActiveButtonService)
	      -> Triggered                     = pemain menekan tombol power
	  Attribute "BatteryPuzzleComplete" pada objek ber-tag "BatteryCase"
	      -> 4 baterai lengkap terpasang
	  Attribute "GeneratorPowered" pada Model generator
	      -> generator menyala

	Sound (semua anak Attachment "GeneratorSFX"):
	  pressing_a_large_industrial_button   one-shot  tombol ditekan
	  electrical_contacts                  one-shot  4 baterai lengkap
	  old_industrial_generator             one-shot  generator baru hidup
	  steady_industrial_generator          LOOP      generator sudah nyala
	  high_voltage_electricity             one-shot  IKUT SINYAL efek listrik

	Urutan: startup (old) diputar dulu -> begitu selesai, loop steady menyusul.
	Jadi tidak tumpang tindih jadi bising.

	=== SUARA LISTRIK (high_voltage_electricity) — BUKAN LOOP ===
	Suara ini TIDAK menyala sendiri saat generator hidup. Ia hanya berbunyi
	kalau script EFEK LISTRIK memberi sinyal, supaya suara & efek visual
	muncul BERSAMAAN. Dua cara memberi sinyal (pilih salah satu):

	  1. BindableEvent "HighVoltage" di ReplicatedStorage
	       game.ReplicatedStorage.HighVoltage:Fire()   -> putar 1x (one-shot)
	     Modul membuat event ini otomatis kalau belum ada, jadi script efek
	     cukup: local sig = RS:WaitForChild("HighVoltage"); sig:Fire()

	  2. Attribute "HighVoltageActive" (Bool) di Model generator
	       gen:SetAttribute("HighVoltageActive", true)   -> nyala & tahan
	       gen:SetAttribute("HighVoltageActive", false)  -> berhenti
	     Dipakai kalau efek listriknya berdurasi panjang: suara diulang terus
	     SELAMA attribute true, lalu berhenti begitu false. Jadi tetap
	     sinkron dengan efeknya, bukan nyala selamanya.

	Syarat: generator harus sudah nyala (Attribute "GeneratorPowered" = true).
	Kalau sinyal datang sementara mesin belum hidup, sinyal DIABAIKAN.
	Sinyal beruntun tidak menumpuk (satu efek = satu suara).

	Cara pakai: GeneratorSFXController.server.luau memanggil start().
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HOST_NAME = "GeneratorSFX"
local PROMPT_NAME = "GeneratorActivatePrompt"
local ATTR_POWERED = "GeneratorPowered"
local ATTR_COMPLETE = "BatteryPuzzleComplete"
local ATTR_HV_ACTIVE = "HighVoltageActive" -- Attribute (Bool) sinyal efek listrik
local HV_EVENT_NAME = "HighVoltage" -- BindableEvent sinyal efek listrik

local SFX_NAMES = {
	Button = "pressing_a_large_industrial_button",
	Contacts = "electrical_contacts",
	Startup = "old_industrial_generator",
	Steady = "steady_industrial_generator",
	HighVoltage = "high_voltage_electricity",
}

-- Jarak dengar maksimum (studs). Nilai bawaan aset = 10000 (terdengar se-map).
-- Untuk horror, suara mesin harus MENGECIL saat pemain menjauh. Ubah di sini saja.
local ROLLOFF_MAX = {
	Button = 60,
	Contacts = 60,
	Startup = 120,
	Steady = 120,
	HighVoltage = 120,
}

-- Nama atribut "baterai lengkap" dibaca dari Config BatteryPuzzle kalau ada,
-- supaya kalau tim mengganti namanya modul ini ikut otomatis. Kalau folder
-- tidak ada, pakai nilai default di atas (modul ini tidak wajib butuh dia).
do
	local modules = script.Parent
	local bp = modules and modules:FindFirstChild("BatteryPuzzle")
	local cfgModule = bp and bp:FindFirstChild("Config")
	if cfgModule then
		local ok, cfg = pcall(require, cfgModule)
		if ok and type(cfg) == "table" and type(cfg.CompletedAttribute) == "string" then
			ATTR_COMPLETE = cfg.CompletedAttribute
		end
	end
end

local GeneratorSFX = {}

local sounds: { [string]: Sound? } = {}
local host: Instance? = nil

local state = {
	started = false,
	hostFound = false,
	promptBound = false,
	powered = false,
	loopsRunning = false,
	contactsPlayed = false,
	hvHeld = false, -- efek listrik sedang berlangsung (attribute true)
	hvPending = false, -- sinyal datang sebelum mesin nyala -> ditahan
}

-- ======================================================================
-- Pencarian objek (tag-driven, bukan path hardcode)
-- ======================================================================

-- Model generator dalam: dari tag "AssemblySlot" naik ke ancestor bernama
-- "Generator". Pola ini sama dengan BatteryPuzzleController supaya tahan
-- dipindah ke folder mana pun.
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

-- Attachment tempat semua Sound berada. Jalur normal: Generator.Case.GeneratorSFX.
-- Cadangan: sapuan Workspace sekali (kalau attachment dipindah manual).
local function findHost(): Instance?
	local gen = findGenerator()
	if gen then
		local case = gen:FindFirstChild("Case")
		if case then
			local att = case:FindFirstChild(HOST_NAME)
			if att then
				return att
			end
		end
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name == HOST_NAME and d:IsA("Attachment") then
			return d
		end
	end
	return nil
end

local function findBatteryCase(): Instance?
	return CollectionService:GetTagged("BatteryCase")[1]
end

local function findButton(gen: Model?): Instance?
	if not gen then
		return nil
	end
	return gen:FindFirstChild("ActiveButton", true)
end

-- ======================================================================
-- Pemutar suara
-- ======================================================================

local function resolveSound(name: string): Sound?
	local h = host
	if not h then
		return nil
	end
	local child = h:FindFirstChild(name)
	if child and child:IsA("Sound") then
		return child
	end
	return nil
end

local function playOneShot(s: Sound?)
	if not s then
		return
	end
	s.Looped = false -- jaring pengaman: one-shot tidak boleh mengulang
	s.TimePosition = 0
	s:Play()
end

local function startLoop(s: Sound?)
	if not s then
		return
	end
	s.Looped = true -- jaring pengaman: loop wajib mengulang
	if s.IsPlaying then
		return
	end
	s:Play()
end

-- ======================================================================
-- Alur kejadian
-- ======================================================================

local function beginLoops()
	if state.loopsRunning then
		return
	end
	state.loopsRunning = true
	startLoop(sounds.Steady)
	-- CATATAN: high_voltage_electricity SENGAJA tidak dinyalakan di sini.
	-- Ia hanya berbunyi kalau script efek listrik memberi sinyal (lihat
	-- fireHighVoltage / setHighVoltageHeld), supaya suara & efek visual
	-- muncul bersamaan. Kalau dinyalakan di sini, ia jadi loop selamanya.
end

-- ======================================================================
-- Suara listrik — BUKAN loop mandiri; ia budak sinyal efek visual
-- ======================================================================

-- Sinyal 1: event "HighVoltage" di-fire -> putar SEKALI.
-- Sinyal diabaikan kalau generator belum nyala, dan tidak menumpuk
-- (satu efek = satu suara).
local function fireHighVoltage()
	if not state.powered then
		return
	end
	local s = sounds.HighVoltage
	if not s then
		return
	end
	if state.hvHeld then
		-- Efek listrik sedang berlangsung (mode tahan): pastikan tetap berbunyi.
		-- JANGAN turunkan jadi one-shot — itu akan memutus efeknya di tengah jalan.
		if not s.IsPlaying then
			s.Looped = true
			s.TimePosition = 0
			s:Play()
		end
		return
	end
	if s.IsPlaying then
		return -- jangan tumpuk; efeknya masih jalan
	end
	playOneShot(s)
end

-- Sinyal 2: Attribute "HighVoltageActive" (Bool) di Model generator.
-- true = suara diulang SELAMA efek listriknya hidup; false = berhenti.
-- Jadi tetap sinkron dengan efeknya, bukan nyala selamanya.
local function setHighVoltageHeld(active: boolean)
	local s = sounds.HighVoltage
	if not s then
		return
	end

	if not active then
		state.hvHeld = false
		state.hvPending = false
		if s.IsPlaying then
			s:Stop()
		end
		s.Looped = false
		return
	end

	if not state.powered then
		-- Mesin belum nyala -> tahan dulu, diterapkan begitu generator hidup.
		state.hvPending = true
		return
	end

	state.hvHeld = true
	state.hvPending = false
	s.Looped = true -- mengulang HANYA selama efeknya hidup
	if not s.IsPlaying then
		s.TimePosition = 0
		s:Play()
	end
end

-- Diterapkan begitu generator nyala: kalau sinyal listrik sudah datang
-- SEBELUM mesin hidup, efeknya baru dimulai sekarang (sinkron dengan efek).
local function applyPendingHighVoltage()
	if not state.powered then
		return
	end
	if not state.hvPending then
		return
	end
	setHighVoltageHeld(true)
end

-- skipStartup = true dipakai kalau generator SUDAH nyala sebelum modul ini
-- jalan (mis. re-run): langsung loop, tanpa memutar ulang suara startup.
local function startPowered(skipStartup: boolean)
	if state.powered then
		return
	end
	state.powered = true

	local startup = sounds.Startup
	if skipStartup or not startup then
		beginLoops()
		applyPendingHighVoltage()
		return
	end

	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		beginLoops()
		applyPendingHighVoltage()
	end

	-- Jaring pengaman: kalau sound gagal dimuat, "Ended" tidak pernah terbit
	-- -> loop tetap dinyalakan setelah perkiraan durasi.
	local waitFor = 3
	if startup.IsLoaded and startup.TimeLength > 0 then
		waitFor = startup.TimeLength
	end
	task.delay(math.max(0.25, waitFor), finish)
	startup.Ended:Once(finish)

	playOneShot(startup)
end

local function bindPrompt(prompt: Instance)
	if state.promptBound then
		return
	end
	state.promptBound = true
	local p = prompt :: ProximityPrompt
	p.Triggered:Connect(function(_player: Player)
		playOneShot(sounds.Button)
	end)
end

-- ======================================================================
-- API
-- ======================================================================

-- opts (semua opsional; kalau kosong semuanya dicari otomatis dari scene):
--   host            : Instance  (Attachment tempat Sound berada)
--   generator       : Model     (Model generator dalam)
--   batteryCase     : Instance  (objek ber-tag "BatteryCase")
--   button          : Instance  (tempat prompt "GeneratorActivatePrompt" menempel)
--   buttonOnSuccess : boolean   (true = suara tombol hanya saat generator BERHASIL nyala;
--                                false/default = bunyi tiap tombol ditekan)
-- Mengembalikan true kalau Attachment sound ketemu & modul siap.
function GeneratorSFX.start(opts: { [string]: any }?): boolean
	opts = opts or {}
	if state.started then
		return state.hostFound
	end
	state.started = true

	host = opts.host or findHost()
	if not host then
		warn("[GeneratorSFX] Attachment '" .. HOST_NAME .. "' tidak ditemukan; suara generator dilewati")
		return false
	end
	state.hostFound = true

	local buttonOnSuccess = opts.buttonOnSuccess == true

	for key, name in pairs(SFX_NAMES) do
		local s = resolveSound(name)
		sounds[key] = s
		if s then
			s.RollOffMaxDistance = ROLLOFF_MAX[key] or 120
		else
			warn("[GeneratorSFX] Sound '" .. name .. "' tidak ada di " .. host:GetFullName())
		end
	end

	local gen = opts.generator or findGenerator()

	-- 1) Tombol power. Prompt-nya dibuat runtime oleh ActiveButtonService,
	--    jadi kalau belum ada kita tunggu (jangan menahan script utama).
	local button = opts.button or findButton(gen)
	if button then
		local prompt = button:FindFirstChild(PROMPT_NAME)
		if prompt then
			bindPrompt(prompt)
		else
			task.spawn(function()
				local p = button:WaitForChild(PROMPT_NAME, 30)
				if p then
					bindPrompt(p)
				else
					warn("[GeneratorSFX] Prompt '" .. PROMPT_NAME .. "' tidak muncul; suara tombol dilewati")
				end
			end)
		end
	else
		warn("[GeneratorSFX] ActiveButton tidak ditemukan; suara tombol dilewati")
	end

	-- 2) 4 baterai lengkap.
	local batteryCase = opts.batteryCase or findBatteryCase()
	if batteryCase then
		if batteryCase:GetAttribute(ATTR_COMPLETE) == true then
			-- Sudah lengkap sebelum modul ini jalan (re-run) -> jangan bunyi retroaktif.
			state.contactsPlayed = true
		end
		batteryCase:GetAttributeChangedSignal(ATTR_COMPLETE):Connect(function()
			if state.contactsPlayed then
				return
			end
			if batteryCase:GetAttribute(ATTR_COMPLETE) == true then
				state.contactsPlayed = true
				playOneShot(sounds.Contacts)
			end
		end)
	else
		warn("[GeneratorSFX] Tidak ada objek ber-tag 'BatteryCase'; suara baterai dilewati")
	end

	-- 3) Generator menyala.
	if gen then
		if gen:GetAttribute(ATTR_POWERED) == true then
			startPowered(true)
		else
			gen:GetAttributeChangedSignal(ATTR_POWERED):Connect(function()
				if gen:GetAttribute(ATTR_POWERED) == true then
					startPowered(false)
				end
			end)
		end

		-- 4) Suara listrik — ikut sinyal script EFEK LISTRIK (bukan loop mandiri).
		-- Sinyal A: BindableEvent "HighVoltage" di ReplicatedStorage -> putar sekali.
		-- Dibuat otomatis kalau belum ada, jadi script efek cukup:
		--     game.ReplicatedStorage:WaitForChild("HighVoltage"):Fire()
		local rs = game:GetService("ReplicatedStorage")
		local hvEvent = rs:FindFirstChild(HV_EVENT_NAME)
		if not hvEvent then
			hvEvent = Instance.new("BindableEvent")
			hvEvent.Name = HV_EVENT_NAME
			hvEvent.Parent = rs
		end
		(hvEvent :: BindableEvent).Event:Connect(fireHighVoltage)

		-- Sinyal B: Attribute "HighVoltageActive" (Bool) -> tahan selama true.
		if gen:GetAttribute(ATTR_HV_ACTIVE) == true then
			setHighVoltageHeld(true)
		end
		gen:GetAttributeChangedSignal(ATTR_HV_ACTIVE):Connect(function()
			setHighVoltageHeld(gen:GetAttribute(ATTR_HV_ACTIVE) == true)
		end)
	else
		warn("[GeneratorSFX] Model generator tidak ditemukan; suara nyala dilewati")
	end

	return true
end

return GeneratorSFX
