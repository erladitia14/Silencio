--[[
	LightManager.luau (KeySystem)
	-----------------------------
	Menyalakan/mematikan semua objek ber-tag "CarnivalLight" secara serempak
	saat PowerService.PowerChanged berubah.

	Dibuat untuk lampu yang SUDAH dibangun tim lain: cukup tempel tag pada
	Part / Model / MeshPart-nya. Sistem mencari objek Light (PointLight,
	SpotLight, SurfaceLight) di SELURUH keturunan objek itu, sedalam apa pun.
	Tidak ada nama instance yang di-hardcode.

	PRINSIP: hormati kerja tim. Brightness, Color, dan Material yang sudah
	di-set tim TIDAK ditimpa nilai karangan sistem — nilai aslinya disimpan
	saat pertama didaftarkan, lalu dipulihkan saat lampu menyala. Attribute
	hanya dipakai kalau tim memang ingin menimpanya.

	  - Ada objek Light di dalamnya -> hanya Light itu yang di-toggle.
	    Material & warna mesh TIDAK disentuh (tekstur tim tetap utuh).
	  - Tidak ada Light sama sekali -> fallback: part di-Neon-kan saat nyala
	    supaya tetap ada efek visual, lalu dikembalikan ke material asli.
	    Matikan fallback ini dengan Attribute KeepMaterial = true.

	Attribute salah tipe (mis. OnBrightness diisi teks) DIABAIKAN + warn,
	bukan error — script ini dipakai tim lain, salah ketik tidak boleh
	menjatuhkan seluruh sistem lampu.

	Objek baru ber-tag yang muncul saat runtime otomatis ikut state terkini.

	CATATAN edit mode: Script server tidak berjalan di edit mode, jadi lampu
	tetap terlihat menyala saat kamu membangun. Lampu baru dimatikan begitu
	Play dimulai (state awal power = OFF).
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local LightManager = {}
LightManager.__index = LightManager

function LightManager.new(powerService: any)
	local self = setmetatable({}, LightManager)
	self._powerService = powerService
	self._lights = {} :: { [Instance]: any }
	self._warned = {} :: { [string]: boolean }
	return self
end

--- Baca Attribute number dengan validasi. Salah tipe/negatif -> nil + warn sekali.
function LightManager:_numberAttr(inst: Instance, name: string): number?
	local value = inst:GetAttribute(name)
	if value == nil then
		return nil
	end
	if typeof(value) ~= "number" or value < 0 then
		local key = inst:GetFullName() .. "." .. name
		if not self._warned[key] then
			self._warned[key] = true
			warn(
				"[KeySystem] Attribute '" .. name .. "' pada '" .. inst.Name
					.. "' harus Number >= 0 (dapat: " .. typeof(value) .. "). Diabaikan."
			)
		end
		return nil
	end
	return value
end

--- Kumpulkan semua objek Light di dalam sebuah instance (termasuk dirinya).
local function collectLights(inst: Instance): { Light }
	local out = {}
	if inst:IsA("Light") then
		table.insert(out, inst)
		return out
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Light") then
			table.insert(out, d)
		end
	end
	return out
end

--- Kumpulkan semua BasePart di dalam sebuah instance (termasuk dirinya).
local function collectParts(inst: Instance): { BasePart }
	local out = {}
	if inst:IsA("BasePart") then
		table.insert(out, inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

--- Terapkan state on/off ke satu objek lampu (Part / Model / MeshPart / Light).
function LightManager:_apply(inst: Instance, isOn: boolean)
	local record = self._lights[inst]
	if not record then return end

	-- Attribute hanya OVERRIDE; nil = pakai nilai asli milik tim.
	local onBright = self:_numberAttr(inst, "OnBrightness")
	local offBright = self:_numberAttr(inst, "OffBrightness")

	-- Di-scan tiap kali supaya Light yang ditambah tim setelah tag tetap kena.
	local lights = collectLights(inst)

	for _, light in ipairs(lights) do
		-- Simpan brightness asli sekali saja: "nyala" = seperti niat tim.
		if record.origBrightness[light] == nil then
			record.origBrightness[light] = light.Brightness
		end

		if isOn then
			light.Enabled = true
			light.Brightness = onBright or record.origBrightness[light]
		elseif offBright and offBright > 0 then
			-- Redup, bukan mati total (berguna untuk nuansa horror).
			light.Enabled = true
			light.Brightness = offBright
		else
			light.Enabled = false
		end
	end

	-- Fallback visual: hanya kalau objek ini benar-benar tidak punya Light.
	-- Tanpa ini, Part polos ber-tag tidak menunjukkan perubahan apa pun.
	if #lights > 0 then return end
	if inst:GetAttribute("KeepMaterial") == true then return end

	for _, part in ipairs(collectParts(inst)) do
		if record.origMaterial[part] == nil then
			record.origMaterial[part] = part.Material
			record.origColor[part] = part.Color
		end
		if isOn then
			part.Material = Enum.Material.Neon
			part.Color = Config.LightOnColor
		else
			part.Material = record.origMaterial[part]
			part.Color = record.origColor[part]
		end
	end
end

function LightManager:register(inst: Instance)
	if self._lights[inst] then return end

	self._lights[inst] = {
		origBrightness = {},
		origMaterial = {},
		origColor = {},
	}

	if #collectLights(inst) == 0 and #collectParts(inst) == 0 then
		warn(
			"[KeySystem] CarnivalLight '" .. inst.Name
				.. "' tidak punya objek Light maupun BasePart. Tidak ada yang bisa dinyalakan."
		)
	end

	-- Sinkronkan langsung ke state power saat ini (saat Play mulai: OFF).
	self:_apply(inst, self._powerService:isPowerOn())
end

--- Terapkan state ke semua lampu (dipanggil saat PowerChanged).
function LightManager:setAll(isOn: boolean)
	for inst in pairs(self._lights) do
		if inst.Parent then
			self:_apply(inst, isOn)
		else
			self._lights[inst] = nil -- bersihkan yang sudah dihapus
		end
	end
end

--- Inisialisasi: daftarkan lampu ber-tag, subscribe PowerChanged, dengarkan runtime.
function LightManager:start()
	for _, inst in CollectionService:GetTagged(Config.CarnivalLightTag) do
		self:register(inst)
	end

	CollectionService:GetInstanceAddedSignal(Config.CarnivalLightTag):Connect(function(inst)
		self:register(inst)
	end)

	self._powerService.PowerChanged:Connect(function(isOn)
		self:setAll(isOn)
	end)
end

return LightManager
