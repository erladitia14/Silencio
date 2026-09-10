--[[
	PeekCamera.luau
	---------------
	Kamera "mengintip dari balik pintu toilet" — modul CLIENT.

	Fitur:
	  1. Kamera Scriptable dipaku di titik `peekCF` bilik toilet.
	  2. Lirikan mouse dibatasi 120° total (±60° kiri-kanan, ±25° atas-bawah).
	  3. Kunci mouse per frame dengan LockCenter agar GetMouseDelta() selalu aktif.
	  4. Keluar Manual: Pemain bisa tekan tombol [E] atau klik prompt layar kapan saja
	     tanpa perlu menunggu oksigen habis!
	  5. Efek Asfiksia / Kehabisan Oksigen:
	     - Suffocation Camera Shake: kepala gemetar panik saat napas < 35%.
	     - Suffocation Blur: pandangan mengabur (Lighting.BlurEffect) saat napas kritis.
	  6. Transisi fade hitam halus saat masuk dan keluar.
	  7. DUA STATE kamera, di-toggle tombol [F]:
	     - HIDDEN  (default saat masuk): kamera di dalam bilik, gelap/hampir buta
	               + vignette hitam. Pemain belum mengintip.
	     - PEEKING (tekan [F]): kamera tween halus ke lubang pintu, bisa lirikan.
	     Tekan [F] lagi untuk kembali ke HIDDEN.
	     --]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PeekCamera = {}
PeekCamera.__index = PeekCamera

local BIND_NAME   = "SilencioSafeZonePeek"
local GUI_NAME    = "SafeZoneFade"
local BLUR_NAME   = "SafeZoneSuffocationBlur"

function PeekCamera.new()
	local self = setmetatable({}, PeekCamera)

	self.player = Players.LocalPlayer
	self.active = false
	self.pending = false
	self.baseCF = nil :: CFrame?
	self.hideCF = nil :: CFrame?   -- posisi kamera "dalam bilik, gelap" (state HIDDEN)
	self.peekCF = nil :: CFrame?   -- posisi kamera "di lubang pintu" (state PEEKING)
	self.state = "HIDDEN"          -- "HIDDEN" | "PEEKING"
	self.yaw = 0
	self.pitch = 0
	self.yawLimit = 60       -- 60° kiri + 60° kanan = 120° total
	self.pitchLimit = 25     -- 25° atas + 25° bawah
	self.sensitivity = 0.35
	self.savedType = nil
	self.savedSubject = nil
	self.savedMouse = nil
	self.inputConn = nil :: RBXScriptConnection?
	self.keyConn = nil :: RBXScriptConnection?

	-- Nilai kepanikan napas (0 = penuh, 1 = habis)
	self.panicIntensity = 0
	self.shakeTick = 0

	-- Blur effect untuk efek kekurangan oksigen
	local blur = Lighting:FindFirstChild(BLUR_NAME)
	if not blur or not blur:IsA("BlurEffect") then
		blur = Instance.new("BlurEffect")
		blur.Name = BLUR_NAME
		blur.Size = 0
		blur.Enabled = true
		blur.Parent = Lighting
	end
	self.blur = blur

	-- ScreenGui untuk fade hitam & hint keluar
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

	-- Hint tombol keluar di pojok kiri atas
	local exitHint = Instance.new("TextButton")
	exitHint.Name = "ExitHint"
	exitHint.AnchorPoint = Vector2.new(0, 0)
	exitHint.Position = UDim2.new(0, 24, 0, 24)
	exitHint.Size = UDim2.new(0, 160, 0, 36)
	exitHint.BackgroundColor3 = Color3.fromRGB(20, 15, 18)
	exitHint.BackgroundTransparency = 0.35
	exitHint.BorderSizePixel = 0
	exitHint.Font = Enum.Font.SpecialElite
	exitHint.TextSize = 14
	exitHint.TextColor3 = Color3.fromRGB(220, 200, 190)
	exitHint.Text = "[E] LEAVE STALL"
	exitHint.AutoButtonColor = true
	exitHint.Visible = false
	exitHint.Parent = gui

	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 4)
	hintCorner.Parent = exitHint

	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = Color3.fromRGB(80, 20, 25)
	hintStroke.Thickness = 1
	hintStroke.Transparency = 0.3
	hintStroke.Parent = exitHint

	exitHint.MouseButton1Click:Connect(function()
		self:requestExit()
	end)

	-- Vignette gelap untuk state HIDDEN (hampir buta di dalam bilik)
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Visible = false
	vignette.ZIndex = 1
	vignette.Parent = gui

	-- Hint tombol [F] untuk toggle ngintip
	local peekHint = Instance.new("TextLabel")
	peekHint.Name = "PeekHint"
	peekHint.AnchorPoint = Vector2.new(0.5, 1)
	peekHint.Position = UDim2.new(0.5, 0, 1, -40)
	peekHint.Size = UDim2.new(0, 220, 0, 36)
	peekHint.BackgroundColor3 = Color3.fromRGB(20, 15, 18)
	peekHint.BackgroundTransparency = 0.35
	peekHint.BorderSizePixel = 0
	peekHint.Font = Enum.Font.SpecialElite
	peekHint.TextSize = 14
	peekHint.TextColor3 = Color3.fromRGB(220, 200, 190)
	peekHint.Text = "[F] PEEK THROUGH HOLE"
	peekHint.Visible = false
	peekHint.Parent = gui

	local peekCorner = Instance.new("UICorner")
	peekCorner.CornerRadius = UDim.new(0, 4)
	peekCorner.Parent = peekHint

	local peekStroke = Instance.new("UIStroke")
	peekStroke.Color = Color3.fromRGB(80, 20, 25)
	peekStroke.Thickness = 1
	peekStroke.Transparency = 0.3
	peekStroke.Parent = peekHint

	self.gui = gui
	self.shade = shade
	self.exitHint = exitHint
	self.vignette = vignette
	self.peekHint = peekHint

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
	self.yaw = math.clamp(self.yaw - dx * self.sensitivity, -self.yawLimit, self.yawLimit)
	self.pitch = math.clamp(self.pitch - dy * self.sensitivity, -self.pitchLimit, self.pitchLimit)
end

function PeekCamera:_attach(peekCF: CFrame, hideCF: CFrame?)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	self.savedType = cam.CameraType
	self.savedSubject = cam.CameraSubject
	self.savedMouse = UserInputService.MouseBehavior

	cam.CameraType = Enum.CameraType.Scriptable
	self.peekCF = peekCF
	-- hideCF = posisi kamera saat HIDDEN (gelap). Default: sama dengan peek
	-- (mundur kompatibel kalau server lama tidak mengirim hideCF).
	self.hideCF = hideCF or peekCF
	self.state = "HIDDEN"
	self.baseCF = self.hideCF
	self.yaw = 0
	self.pitch = 0
	self.panicIntensity = 0
	self.shakeTick = 0

	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end)

	-- Masuk = state HIDDEN: vignette gelap nyala, hint [F] muncul
	self:_applyHiddenVisual(true)

	-- Tampilkan tombol keluar manual
	if self.exitHint then
		self.exitHint.Visible = true
	end

	-- Hentikan animasi lari/jalan client secara instan (bug playtest Aer)
	local char = self.player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			local name = track.Name:lower()
			local anim = track.Animation
			local animName = anim and anim.Name:lower() or ""
			if name:find("run") or name:find("walk") or name:find("sprint")
				or animName:find("run") or animName:find("walk")
				or track.Priority == Enum.AnimationPriority.Movement then
				track:Stop(0.1)
			end
		end
	end

	-- RenderStep Loop: Update rotasi kamera, mouse delta, & suffocation shake
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not self.active then
			return
		end

		local base = self.baseCF
		local c = workspace.CurrentCamera
		if not base or not c then
			return
		end

		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			end)
		end

		local delta = UserInputService:GetMouseDelta()
		self:_look(delta.X, delta.Y)

		-- Rotasi dasar bilik + Yaw + Pitch
		local basePos = base.Position
		local baseRot = base.Rotation
		local yawRot = CFrame.Angles(0, math.rad(self.yaw), 0)
		local pitchRot = CFrame.Angles(math.rad(self.pitch), 0, 0)
		local finalCF = CFrame.new(basePos) * (baseRot * yawRot * pitchRot)

		-- Suffocation Camera Shake saat oksigen menipis
		if self.panicIntensity > 0 then
			self.shakeTick += dt * (12 + self.panicIntensity * 10)
			local shakeAmount = math.rad(0.3 + self.panicIntensity * 2.2)
			local shake = CFrame.Angles(
				math.noise(self.shakeTick, 0, 0) * shakeAmount,
				math.noise(0, self.shakeTick, 0) * shakeAmount,
				math.noise(0, 0, self.shakeTick) * (shakeAmount * 0.5)
			)
			finalCF = finalCF * shake
		end

		c.CFrame = finalCF
	end)

	-- Listener Touch untuk Mobile
	self.inputConn = UserInputService.InputChanged:Connect(function(input, processed)
		if not self.active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			self:_look(input.Delta.X, input.Delta.Y)
		end
	end)

	-- Keybind Keluar Cepat: Tombol E atau Space
	-- Keybind Toggle Ngintip: Tombol F
	self.keyConn = UserInputService.InputBegan:Connect(function(input, processed)
		if not self.active or processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space then
			self:requestExit()
		elseif input.KeyCode == Enum.KeyCode.F then
			self:togglePeek()
		end
	end)

	self.active = true
end

---------------------------------------------------------------------
-- STATE HIDDEN <-> PEEKING
---------------------------------------------------------------------

--- Nyalakan/matikan visual state HIDDEN (vignette gelap + hint [F]).
function PeekCamera:_applyHiddenVisual(isHidden: boolean)
	if self.vignette then
		self.vignette.Visible = true
		local target = isHidden and 0.55 or 1
		TweenService:Create(self.vignette, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			BackgroundTransparency = target,
		}):Play()
		if not isHidden then
			task.delay(0.35, function()
				if self.vignette and self.state ~= "HIDDEN" then
					self.vignette.Visible = false
				end
			end)
		end
	end
	if self.peekHint then
		self.peekHint.Text = isHidden and "[F] PEEK THROUGH HOLE" or "[F] STOP PEEKING"
		self.peekHint.Visible = true
	end
end

--- Toggle HIDDEN <-> PEEKING dengan tween kamera halus.
function PeekCamera:togglePeek()
	if not self.active then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	if self.state == "HIDDEN" then
		-- -> PEEKING: tween ke lubang pintu
		self.state = "PEEKING"
		self:_applyHiddenVisual(false)
		self:_tweenCameraTo(self.peekCF, 0.5)
	else
		-- -> HIDDEN: tween balik ke posisi gelap
		self.state = "HIDDEN"
		self:_applyHiddenVisual(true)
		self:_tweenCameraTo(self.hideCF, 0.5)
	end
end

--- Tween baseCF ke target selama `duration` detik. RenderStep loop membaca
--- baseCF tiap frame, jadi kita animasikan baseCF (bukan cam.CFrame langsung).
function PeekCamera:_tweenCameraTo(targetCF: CFrame, duration: number)
	if not targetCF then
		return
	end
	local fromCF = self.baseCF or targetCF
	-- Reset lirikan supaya masuk ke posisi baru tanpa offset aneh
	self.yaw = 0
	self.pitch = 0

	local startTime = os.clock()
	local dur = math.max(0.05, duration)
	-- Matikan baseCF sementara supaya RenderStep tidak menimpa tween kita
	local savedBase = self.baseCF
	self._tweening = true

	task.spawn(function()
		while true do
			local alpha = math.clamp((os.clock() - startTime) / dur, 0, 1)
			-- Ease in-out quad
			local ease = alpha < 0.5 and 2 * alpha * alpha or 1 - ((-2 * alpha + 2) ^ 2) / 2
			self.baseCF = fromCF:Lerp(targetCF, ease)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		self.baseCF = targetCF
		self._tweening = false
	end)
end

function PeekCamera:_detach()
	self.active = false
	self.baseCF = nil
	self.hideCF = nil
	self.peekCF = nil
	self.state = "HIDDEN"
	self._tweening = false
	self.panicIntensity = 0

	if self.inputConn then
		self.inputConn:Disconnect()
		self.inputConn = nil
	end

	if self.keyConn then
		self.keyConn:Disconnect()
		self.keyConn = nil
	end

	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)

	if self.exitHint then
		self.exitHint.Visible = false
	end

	if self.vignette then
		self.vignette.Visible = false
		self.vignette.BackgroundTransparency = 1
	end

	if self.peekHint then
		self.peekHint.Visible = false
	end

	-- Pulihkan Blur
	if self.blur then
		TweenService:Create(self.blur, TweenInfo.new(0.3), { Size = 0 }):Play()
	end

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
-- KONTROL EFEK SUFFOCATION DARI LUAR (dipanggil saat breath berkurang)
---------------------------------------------------------------------

function PeekCamera:setBreathFraction(fraction: number)
	if not self.active then
		return
	end

	-- Efek asfiksia mulai muncul ketika napas < 45%
	if fraction <= 0.45 then
		-- Intensity dari 0 (saat 45%) hingga 1.0 (saat 0%)
		local intensity = math.clamp((0.45 - fraction) / 0.45, 0, 1)
		self.panicIntensity = intensity

		-- Blur penglihatan (0 hingga 16) seolah mau pingsan
		if self.blur then
			self.blur.Size = math.floor(intensity * 16)
		end
	else
		self.panicIntensity = 0
		if self.blur and self.blur.Size > 0 then
			self.blur.Size = 0
		end
	end
end

---------------------------------------------------------------------
-- REQUEST EXIT (Client -> Server)
---------------------------------------------------------------------

function PeekCamera:requestExit()
	if not self.active then
		return
	end
	local remote = ReplicatedStorage:FindFirstChild("SafeZoneState")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer({ action = "LEAVE" })
	end
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
	-- hideCF opsional (server lama mungkin tidak mengirimnya)
	local hideCF = payload.hideCF
	if typeof(hideCF) ~= "CFrame" then
		hideCF = nil
	end

	self.pending = true
	task.spawn(function()
		self:_fadeThrough(tonumber(payload.fade) or 0.35, function()
			if self.pending then
				self:_attach(peekCF, hideCF)
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
	if self.exitHint then
		self.exitHint.Visible = false
	end
	if self.vignette then
		self.vignette.Visible = false
		self.vignette.BackgroundTransparency = 1
	end
	if self.peekHint then
		self.peekHint.Visible = false
	end
	if self.blur then
		self.blur.Size = 0
	end
end

function PeekCamera:destroy()
	self:forceRelease()
	if self.gui then
		self.gui:Destroy()
	end
	if self.blur then
		self.blur:Destroy()
	end
	self.gui = nil
	self.shade = nil
	self.exitHint = nil
	self.vignette = nil
	self.peekHint = nil
	self.blur = nil
end

return PeekCamera
