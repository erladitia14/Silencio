--[[
	PeekCamera.luau
	---------------
	Kamera "mengintip dari balik pintu toilet" — modul CLIENT.

	Saat pemain sembunyi, kamera dilepas dari karakter dan dipaku di titik
	`PeekPoint` bilik, menghadap keluar pintu. Pemain masih bisa melirik
	kiri-kanan/atas-bawah, tapi TERBATAS: ia sedang terkurung, bukan bebas
	memutar 360 derajat.

	Plus transisi gelap (fade) saat masuk & keluar. Ini PENGGANTI SEMENTARA
	animasi masuk-bilik dan animasi monster menarik pemain keluar — begitu
	aset animasinya ada, fade bisa dikurangi atau dibuang.

	KENAPA DI CLIENT: `Camera` itu objek lokal; server tidak boleh (dan tidak
	bisa) menyetirnya. Server cuma mengirim titik intip + arah pintu.

	Murni presentasi: modul ini tidak memutuskan apa pun soal aturan game.
	Kalau ia gagal/di-nonaktifkan, sistem napas & perlindungan tetap jalan.
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local PeekCamera = {}
PeekCamera.__index = PeekCamera

local BIND_NAME = "SafeZonePeek"
local GUI_NAME  = "SafeZoneFade"

---------------------------------------------------------------------

function PeekCamera.new()
	local self = setmetatable({}, PeekCamera)

	self.player = Players.LocalPlayer
	self.active = false
	self.baseCF = nil :: CFrame?
	self.yaw = 0
	self.pitch = 0
	self.yawLimit = 45
	self.pitchLimit = 22
	self.sensitivity = 0.25
	self.savedType = nil
	self.savedSubject = nil
	self.inputConn = nil :: RBXScriptConnection?

	-- Layar hitam untuk transisi. ResetOnSpawn=false: harus selamat dari
	-- respawn, kalau tidak pemain bisa terjebak layar hitam permanen.
	local gui = self.player:WaitForChild("PlayerGui"):FindFirstChild(GUI_NAME)
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 20
		gui.Parent = self.player:WaitForChild("PlayerGui")
	end
	gui:ClearAllChildren()

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Active = false          -- jangan blokir klik pemain
	shade.Visible = false
	shade.Parent = gui

	self.gui = gui
	self.shade = shade

	return self
end

---------------------------------------------------------------------
-- TRANSISI
---------------------------------------------------------------------

--- Gelap lalu terang, dengan `midpoint` dijalankan saat layar paling hitam.
function PeekCamera:_fadeThrough(duration: number, midpoint: () -> ())
	local half = math.max(0.05, duration) / 2
	local shade = self.shade

	shade.Visible = true
	local inTween = TweenService:Create(shade, TweenInfo.new(half), { BackgroundTransparency = 0 })
	inTween:Play()
	inTween.Completed:Wait()

	local ok, err = pcall(midpoint)
	if not ok then
		warn("[SafeZone] transisi kamera gagal: " .. tostring(err))
	end

	local outTween = TweenService:Create(shade, TweenInfo.new(half), { BackgroundTransparency = 1 })
	outTween:Play()
	outTween.Completed:Wait()
	shade.Visible = false
end

---------------------------------------------------------------------
-- MENGINTIP
---------------------------------------------------------------------

function PeekCamera:_bindLook()
	if self.inputConn then
		return
	end
	-- Delta mouse/sentuh -> lirikan terbatas. Tidak memakai
	-- MouseBehavior.LockCenter supaya pemain tetap bisa klik UI.
	self.inputConn = UserInputService.InputChanged:Connect(function(input, processed)
		if not self.active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Delta
			self.yaw = math.clamp(self.yaw - d.X * self.sensitivity, -self.yawLimit, self.yawLimit)
			self.pitch = math.clamp(self.pitch - d.Y * self.sensitivity, -self.pitchLimit, self.pitchLimit)
		end
	end)
end

function PeekCamera:_unbindLook()
	if self.inputConn then
		self.inputConn:Disconnect()
		self.inputConn = nil
	end
end

--- Pasang kamera di titik intip.
function PeekCamera:_attach(peekCF: CFrame)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	self.savedType = cam.CameraType
	self.savedSubject = cam.CameraSubject

	cam.CameraType = Enum.CameraType.Scriptable
	self.baseCF = peekCF
	self.yaw, self.pitch = 0, 0

	-- RenderPriority.Camera + 1: sama seperti DamageEffect. Urutan
	-- RenderStepped tidak dijamin, jadi kamera bisa ditimpa modul lain
	-- di frame yang sama kalau memakai :Connect biasa.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local base = self.baseCF
		local c = workspace.CurrentCamera
		if not base or not c then
			return
		end
		c.CFrame = base * CFrame.Angles(math.rad(self.pitch), math.rad(self.yaw), 0)
	end)

	self:_bindLook()
	self.active = true
end

--- Lepas kamera, kembalikan ke karakter.
function PeekCamera:_detach()
	self.active = false
	self.baseCF = nil
	self:_unbindLook()

	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)

	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = self.savedType or Enum.CameraType.Custom
		local char = self.player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = self.savedSubject or humanoid
	end
	self.savedType, self.savedSubject = nil, nil
end

---------------------------------------------------------------------
-- API (dipanggil SafeZoneUI saat menerima pesan server)
---------------------------------------------------------------------

--- Pemain masuk bilik: fade gelap -> pasang kamera intip -> fade terang.
function PeekCamera:enter(payload: { [string]: any })
	if self.active then
		return
	end
	self.yawLimit   = tonumber(payload.yawLimit) or self.yawLimit
	self.pitchLimit = tonumber(payload.pitchLimit) or self.pitchLimit

	local peekCF = payload.peekCF
	if typeof(peekCF) ~= "CFrame" then
		warn("[SafeZone] peekCF tidak sah -> kamera intip dilewati.")
		return
	end

	task.spawn(function()
		self:_fadeThrough(tonumber(payload.fade) or 0.35, function()
			self:_attach(peekCF)
		end)
	end)
end

--- Pemain keluar bilik: fade gelap -> lepas kamera -> fade terang.
function PeekCamera:exit(payload: { [string]: any }?)
	if not self.active then
		return
	end
	task.spawn(function()
		self:_fadeThrough(tonumber(payload and payload.fade) or 0.35, function()
			self:_detach()
		end)
	end)
end

--- Paksa lepas tanpa transisi (respawn / karakter hilang).
function PeekCamera:forceRelease()
	if self.active then
		self:_detach()
	end
	self.shade.BackgroundTransparency = 1
	self.shade.Visible = false
end

function PeekCamera:destroy()
	self:forceRelease()
	if self.gui then
		self.gui:Destroy()
	end
	self.gui = nil
	self.shade = nil
end

return PeekCamera
