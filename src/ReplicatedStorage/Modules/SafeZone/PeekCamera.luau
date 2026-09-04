--[[
	PeekCamera.luau
	---------------
	Kamera "mengintip dari balik pintu toilet" — modul CLIENT.

	Fitur:
	  1. Kamera Scriptable dipaku di titik `peekCF` bilik.
	  2. Lirikan mouse & touch dibatasi 120° total (±60° kiri-kanan, ±25° atas-bawah).
	  3. Mouse di-lock per frame di RenderStep agar GetMouseDelta() selalu terisi
	     dan tidak ditimpa oleh CameraModule default Roblox.
	  4. Rumus rotasi First-Person:
	       CFrame.new(base.Position) * base.Rotation * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	     Mencegah roll/miring aneh.
	  5. Transisi fade hitam halus saat masuk dan keluar.
	  6. Layar bebas dari layar hitam nyangkut (safety cleanup).
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local PeekCamera = {}
PeekCamera.__index = PeekCamera

local BIND_NAME = "SilencioSafeZonePeek"
local GUI_NAME  = "SafeZoneFade"

function PeekCamera.new()
	local self = setmetatable({}, PeekCamera)

	self.player = Players.LocalPlayer
	self.active = false
	self.pending = false
	self.baseCF = nil :: CFrame?
	self.yaw = 0
	self.pitch = 0
	self.yawLimit = 60       -- 60° kiri + 60° kanan = 120° total (permintaan Aer)
	self.pitchLimit = 25     -- 25° atas + 25° bawah
	self.sensitivity = 0.35
	self.savedType = nil
	self.savedSubject = nil
	self.savedMouse = nil
	self.inputConn = nil :: RBXScriptConnection?

	-- Layar transisi hitam
	local playerGui = self.player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(GUI_NAME) or Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25
	gui.Parent = playerGui
	gui:ClearAllChildren()

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Active = false
	shade.Visible = false
	shade.Parent = gui

	self.gui = gui
	self.shade = shade

	return self
end

---------------------------------------------------------------------
-- TRANSISI FADE
---------------------------------------------------------------------

function PeekCamera:_fadeThrough(duration: number, midpoint: () -> ())
	local half = math.max(0.06, duration) / 2
	local shade = self.shade
	if not shade then
		pcall(midpoint)
		return
	end

	shade.Visible = true
	local inTween = TweenService:Create(shade, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	})
	inTween:Play()
	inTween.Completed:Wait()

	local ok, err = pcall(midpoint)
	if not ok then
		warn("[SafeZone] error di midpoint kamera: " .. tostring(err))
	end

	local outTween = TweenService:Create(shade, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1
	})
	outTween:Play()
	outTween.Completed:Wait()
	shade.Visible = false
end

---------------------------------------------------------------------
-- MENGINTIP & LIRIKAN
---------------------------------------------------------------------

function PeekCamera:_look(dx: number, dy: number)
	if dx == 0 and dy == 0 then
		return
	end
	-- Mouse geser ke kanan (dx > 0) -> kamera belok ke kanan (yaw negatif di CFrame Y)
	self.yaw = math.clamp(self.yaw - dx * self.sensitivity, -self.yawLimit, self.yawLimit)
	-- Mouse geser ke atas (dy < 0) -> kamera mendongak ke atas (pitch positif di CFrame X)
	self.pitch = math.clamp(self.pitch - dy * self.sensitivity, -self.pitchLimit, self.pitchLimit)
end

function PeekCamera:_attach(peekCF: CFrame)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	self.savedType = cam.CameraType
	self.savedSubject = cam.CameraSubject
	self.savedMouse = UserInputService.MouseBehavior

	cam.CameraType = Enum.CameraType.Scriptable
	self.baseCF = peekCF
	self.yaw = 0
	self.pitch = 0

	-- Kunci mouse agar GetMouseDelta() terus membaca gerakan kursor
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end)

	-- RenderPriority.Camera.Value + 1: dieksekusi tepat setelah Camera default
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if not self.active then
			return
		end

		local base = self.baseCF
		local c = workspace.CurrentCamera
		if not base or not c then
			return
		end

		-- Jaga MouseBehavior tetap LockCenter setiap frame agar tidak di-reset CameraModule
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			end)
		end

		-- Baca pergerakan mouse delta frame ini
		local delta = UserInputService:GetMouseDelta()
		self:_look(delta.X, delta.Y)

		-- Rumus rotasi First-Person yang bersih:
		-- Rotasi dasar bilik -> rotasi Yaw (kiri-kanan) -> rotasi Pitch (atas-bawah)
		local basePos = base.Position
		local baseRot = base.Rotation
		local yawRot = CFrame.Angles(0, math.rad(self.yaw), 0)
		local pitchRot = CFrame.Angles(math.rad(self.pitch), 0, 0)

		c.CFrame = CFrame.new(basePos) * (baseRot * yawRot * pitchRot)
	end)

	-- Listener Touch untuk perangkat Mobile
	self.inputConn = UserInputService.InputChanged:Connect(function(input, processed)
		if not self.active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			self:_look(input.Delta.X, input.Delta.Y)
		end
	end)

	self.active = true
end

function PeekCamera:_detach()
	self.active = false
	self.baseCF = nil

	if self.inputConn then
		self.inputConn:Disconnect()
		self.inputConn = nil
	end

	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)

	-- Pulihkan MouseBehavior
	pcall(function()
		UserInputService.MouseBehavior = self.savedMouse or Enum.MouseBehavior.Default
	end)

	-- Pulihkan Camera
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = self.savedType or Enum.CameraType.Custom
		local char = self.player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = self.savedSubject or humanoid
	end
	self.savedType, self.savedSubject, self.savedMouse = nil, nil, nil
end

---------------------------------------------------------------------
-- API EKSTERNAL
---------------------------------------------------------------------

function PeekCamera:enter(payload: { [string]: any })
	if self.active then
		return
	end

	self.yawLimit = tonumber(payload.yawLimit) or self.yawLimit
	self.pitchLimit = tonumber(payload.pitchLimit) or self.pitchLimit
	self.sensitivity = tonumber(payload.sensitivity) or self.sensitivity

	local peekCF = payload.peekCF
	if typeof(peekCF) ~= "CFrame" then
		warn("[SafeZone] peekCF tidak valid -> kamera intip dilewati.")
		return
	end

	self.pending = true
	task.spawn(function()
		self:_fadeThrough(tonumber(payload.fade) or 0.35, function()
			if self.pending then
				self:_attach(peekCF)
			end
		end)
		self.pending = false
	end)
end

function PeekCamera:exit(payload: { [string]: any }?)
	local wasPending = self.pending
	self.pending = false

	if not self.active then
		if wasPending then
			self:forceRelease()
		end
		return
	end

	task.spawn(function()
		self:_fadeThrough(tonumber(payload and payload.fade) or 0.35, function()
			self:_detach()
		end)
	end)
end

function PeekCamera:forceRelease()
	self.pending = false
	if self.active then
		self:_detach()
	end
	if self.shade then
		self.shade.BackgroundTransparency = 1
		self.shade.Visible = false
	end
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
