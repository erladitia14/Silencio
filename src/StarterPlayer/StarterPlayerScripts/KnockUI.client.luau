--[[
	KnockUI.client.luau
	-------------------
	LocalScript penghubung: memantau SEMUA karakter yang ber-Attribute
	"Knocked" = true, lalu menampilkan billboard sisa waktu bleed-out di atas
	kepala mereka (lihat modul KnockHud).

	Letak: StarterPlayer/StarterPlayerScripts

	Script ini SENGAJA setipis mungkin — nol logika tampilan. Kalau tim punya
	desain UI sendiri, cukup ganti UI_MODULE (atau tukar isi modulnya);
	server & mekanisme knock tidak perlu disentuh.

	Kontrak modul UI: new(adornee) -> objek, objek:update(payload|nil),
	objek:tick(now), objek:destroy()

	DATA (semua dari server, replikasi otomatis — tidak ada RemoteEvent baru):
	  Attribute karakter "Knocked"              (Bool)
	  Attribute karakter "KnockBleedOut"        (Number, sisa detik)
	  Attribute karakter "KnockReviveProgress"  (Number, 0..1)
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI_MODULE = "KnockHud"   -- ganti kalau tim punya modul UI sendiri

-- Nama Attribute (disamakan dengan KnockSystem/Config; sengaja tidak
-- me-require Config supaya UI tetap jalan walau modul server tak dimuat).
local ATTR_DOWNED   = "Knocked"
local ATTR_BLEEDOUT = "KnockBleedOut"
local ATTR_REVIVE   = "KnockReviveProgress"

local PLAYER = Players.LocalPlayer

---------------------------------------------------------------------
-- MUAT MODUL PRESENTASI (opsional; gagal tidak boleh menjatuhkan script)
---------------------------------------------------------------------
local function loadHudModule(): any?
	local modules = ReplicatedStorage:WaitForChild("Modules", 20)
	local folder = modules and modules:WaitForChild("KnockSystem", 20)
	if not folder then
		warn("[KnockUI] Folder modul KnockSystem tidak ditemukan -> UI tidak dipasang.")
		return nil
	end
	local mod = folder:FindFirstChild(UI_MODULE)
	if not mod or not mod:IsA("ModuleScript") then
		warn("[KnockUI] Modul '" .. UI_MODULE .. "' tidak ditemukan.")
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[KnockUI] Modul '" .. UI_MODULE .. "' gagal dimuat -> " .. tostring(result))
		return nil
	end
	return result
end

--- Tinggi billboard di atas root. Dibaca OPSIONAL dari Config supaya UI tetap
--- jalan walau modul server tak dimuat (Config cuma untuk tuning tampilan).
local function loadHudHeight(): number?
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local folder = modules and modules:FindFirstChild("KnockSystem")
	local cfg = folder and folder:FindFirstChild("Config")
	if not cfg or not cfg:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, cfg)
	if ok and type(result) == "table" then
		local h = result.KnockHudHeight
		if type(h) == "number" and h >= 0 then
			return h
		end
	end
	return nil
end

local HudClass = loadHudModule()
if not HudClass then
	return
end

local HUD_HEIGHT = loadHudHeight()

---------------------------------------------------------------------
-- REGISTRY: satu HUD per karakter tumbang
---------------------------------------------------------------------
-- [character] = { hud, adornee }
local active: { [Model]: any } = {}

local function getAdornee(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Head")
		or character:FindFirstChildOfClass("BasePart")
end

local function attach(character: Model)
	if active[character] then
		return
	end
	local adornee = getAdornee(character)
	if not adornee then
		return
	end
	local ok, hud = pcall(function()
		return HudClass.new(adornee, HUD_HEIGHT)
	end)
	if not ok or not hud then
		warn("[KnockUI] gagal membuat HUD -> " .. tostring(hud))
		return
	end
	active[character] = { hud = hud, adornee = adornee }
end

local function detach(character: Model?)
	if not character then
		return
	end
	local rec = active[character]
	active[character] = nil
	if rec and rec.hud then
		pcall(function() rec.hud:destroy() end)
	end
end

---------------------------------------------------------------------
-- SINKRONISASI ATTRIBUTE -> HUD
---------------------------------------------------------------------
local function refresh(character: Model)
	local rec = active[character]
	if not rec then
		return
	end

	local isDowned = character:GetAttribute(ATTR_DOWNED) == true
	if not isDowned then
		detach(character)
		return
	end

	-- Adornee bisa berganti (karakter baru / root diganti).
	local adornee = getAdornee(character)
	if adornee and adornee ~= rec.adornee then
		rec.adornee = adornee
		if rec.hud.billboard then
			rec.hud.billboard.Adornee = adornee
		end
	end

	local bleedOut = tonumber(character:GetAttribute(ATTR_BLEEDOUT)) or 0
	local revive   = tonumber(character:GetAttribute(ATTR_REVIVE)) or 0

	-- Total bleed-out tidak dikirim server; pakai nilai terbesar yang pernah
	-- terlihat sebagai perkiraan supaya bar proporsional. Ini murni tampilan.
	local total = rec.total
	if not total or bleedOut > total then
		total = math.max(bleedOut, 1)
		rec.total = total
	end

	local owner = Players:GetPlayerFromCharacter(character)
	local payload = {
		name           = owner and owner.Name or character.Name,
		bleedOut       = bleedOut,
		total          = total,
		fraction       = math.clamp(bleedOut / total, 0, 1),
		reviveProgress = revive,
	}

	rec.hud:update(payload)
end

local function onAttributeChanged(character: Model, attr: string)
	if attr ~= ATTR_DOWNED and attr ~= ATTR_BLEEDOUT and attr ~= ATTR_REVIVE then
		return
	end
	if attr == ATTR_DOWNED and character:GetAttribute(ATTR_DOWNED) == true then
		attach(character)
	end
	refresh(character)
end

local function watchCharacter(character: Model)
	if character:GetAttribute(ATTR_DOWNED) == true then
		attach(character)
		refresh(character)
	end
	character.AttributeChanged:Connect(function(attr)
		onAttributeChanged(character, attr)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			detach(character)
		end
	end)
end

-- Karakter yang sudah ada
for _, player in Players:GetPlayers() do
	if player.Character then
		watchCharacter(player.Character)
	end
end

-- Karakter baru (termasuk milik sendiri saat respawn)
local function watchPlayer(player: Player)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(function(character)
		detach(character)
	end)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player)
	-- HUD karakter pemain itu ikut hilang bersama karakternya.
	if player.Character then
		detach(player.Character)
	end
end)

---------------------------------------------------------------------
-- DENYUT (hanya saat panik) — satu loop untuk semua HUD
---------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for character, rec in active do
		if character.Parent and rec.hud then
			if rec.hud.tick then
				pcall(function() rec.hud:tick(now) end)
			end
		end
	end
end)

-- Respawn: jangan tinggalkan billboard nyangkut
PLAYER.CharacterAdded:Connect(function(character)
	watchCharacter(character)
end)
