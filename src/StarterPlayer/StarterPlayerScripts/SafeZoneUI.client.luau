--[[
	SafeZoneUI.client.luau
	----------------------
	LocalScript penghubung: dengarkan RemoteEvent "SafeZoneState", lalu
	serahkan ke dua modul presentasi.

	Letak: StarterPlayer/StarterPlayerScripts

	Script ini SENGAJA setipis mungkin — nol logika tampilan:
	  kind = STATE  -> modul UI (bar napas)
	  kind = ENTER  -> PeekCamera (fade + kamera mengintip)
	  kind = EXIT   -> PeekCamera (fade + kamera normal)

	Kalau tim mengirim desain UI sendiri, cukup ganti UI_MODULE (atau tukar
	isi modulnya). Kamera & server tidak perlu disentuh.

	Kontrak modul UI: new() -> objek, objek:update(payload), objek:destroy()
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI_MODULE = "BreathBar"   -- ganti kalau tim punya modul UI sendiri

local modules = ReplicatedStorage:WaitForChild("Modules", 20)
local folder = modules and modules:WaitForChild("SafeZone", 20)
if not folder then
	warn("[SafeZone] Folder modul SafeZone tidak ditemukan -> UI napas tidak dipasang.")
	return
end

local Config = require(folder:WaitForChild("Config"))
local E = Config.Event

---------------------------------------------------------------------
-- MUAT MODUL PRESENTASI (dua-duanya opsional; gagal satu tidak
-- boleh menjatuhkan yang lain)
---------------------------------------------------------------------

local function loadModule(name: string): any?
	local mod = folder:FindFirstChild(name)
	if not mod or not mod:IsA("ModuleScript") then
		warn("[SafeZone] Modul '" .. name .. "' tidak ditemukan.")
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[SafeZone] Modul '" .. name .. "' gagal dimuat -> " .. tostring(result))
		return nil
	end
	return result
end

local UI = loadModule(UI_MODULE)
local PeekCameraClass = loadModule("PeekCamera")

local bar = nil
if UI then
	local ok, result = pcall(function() return UI.new() end)
	bar = ok and result or nil
	if not ok then
		warn("[SafeZone] UI napas gagal dibuat -> " .. tostring(result))
	end
end

local camera = nil
if PeekCameraClass then
	local ok, result = pcall(function() return PeekCameraClass.new() end)
	camera = ok and result or nil
	if not ok then
		warn("[SafeZone] Kamera intip gagal dibuat -> " .. tostring(result))
	end
end

---------------------------------------------------------------------
-- REMOTE
---------------------------------------------------------------------

local remote = ReplicatedStorage:WaitForChild(Config.RemoteName, 20)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[SafeZone] RemoteEvent '" .. Config.RemoteName .. "' tidak ditemukan.")
	return
end

local function safe(fn)
	local ok, err = pcall(fn)
	if not ok then
		warn("[SafeZone] " .. tostring(err))
	end
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	-- Pesan tanpa `kind` = pembaruan bar napas (bentuk lama). Ditoleransi
	-- supaya modul UI buatan tim yang mengikuti dokumen versi awal
	-- tidak mendadak rusak.
	local kind = payload.kind or E.STATE

	if kind == E.STATE then
		if bar then
			safe(function() bar:update(payload) end)
		end

	elseif kind == E.ENTER then
		if camera then
			safe(function() camera:enter(payload) end)
		end

	elseif kind == E.EXIT then
		if camera then
			safe(function() camera:exit(payload) end)
		end
		-- Bar disembunyikan lewat pesan STATE "NONE" yang menyusul.
	end
end)

---------------------------------------------------------------------
-- RESPAWN: jangan tinggalkan kamera/layar hitam nyangkut
---------------------------------------------------------------------

Players.LocalPlayer.CharacterAdded:Connect(function()
	if camera then
		safe(function() camera:forceRelease() end)
	end
	if bar then
		safe(function() bar:update(nil) end)
	end
end)
