--[[
	SafeZoneUI.client.luau
	----------------------
	LocalScript penghubung: dengarkan RemoteEvent "SafeZoneState" dari
	server, lalu serahkan ke modul UI.

	Letak: StarterPlayer/StarterPlayerScripts

	Script ini SENGAJA setipis mungkin — tidak ada logika tampilan di
	sini. Kalau tim mengirim desain UI sendiri, cukup ganti nama modul di
	konstanta UI_MODULE (atau tukar isi modulnya). Tidak ada yang lain
	yang perlu disentuh.

	Kontrak modul UI: new() -> objek, objek:update(payload), objek:destroy()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI_MODULE = "BreathBar"   -- ganti kalau tim punya modul UI sendiri

local modules = ReplicatedStorage:WaitForChild("Modules", 20)
local folder = modules and modules:WaitForChild("SafeZone", 20)
if not folder then
	warn("[SafeZone] Folder modul SafeZone tidak ditemukan -> UI napas tidak dipasang.")
	return
end

local Config = require(folder:WaitForChild("Config"))

local uiModule = folder:FindFirstChild(UI_MODULE)
if not uiModule or not uiModule:IsA("ModuleScript") then
	warn("[SafeZone] Modul UI '" .. UI_MODULE .. "' tidak ditemukan -> UI napas tidak dipasang.")
	return
end

local okLoad, UI = pcall(require, uiModule)
if not okLoad then
	warn("[SafeZone] Modul UI gagal dimuat -> " .. tostring(UI))
	return
end

local remote = ReplicatedStorage:WaitForChild(Config.RemoteName, 20)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[SafeZone] RemoteEvent '" .. Config.RemoteName .. "' tidak ditemukan -> UI napas tidak dipasang.")
	return
end

local bar = UI.new()

remote.OnClientEvent:Connect(function(payload)
	local ok, err = pcall(function()
		bar:update(payload)
	end)
	if not ok then
		warn("[SafeZone] UI napas gagal digambar: " .. tostring(err))
	end
end)
