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
local GuiService        = game:GetService("GuiService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anchors           = require(script.Parent.Anchors)

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

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
	local playerGui = self.player and (self.player:FindFirstChildOfClass("PlayerGui") or self.player:WaitForChild("PlayerGui", 5))
	if not playerGui then
		playerGui = Instance.new("Folder")
	end
	local gui = playerGui:FindFirstChild(GUI_NAME) or Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.ClipToDeviceSafeArea = false
	end)
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

	-- Hitung margin atas dinamis agar aman dari tombol menu/chat Roblox & poni/notch HP
	local topInset = 0
	pcall(function()
		topInset = GuiService:GetGuiInset().Y
	end)
	local baseY = math.max(54, topInset + 10)

	-- Hint tombol keluar di pojok kiri atas (posisi di bawah Safe Area / Topbar Roblox)
	local exitHint = Instance.new("TextButton")
	exitHint.Name = "ExitHint"
	exitHint.AnchorPoint = Vector2.new(0, 0)
	exitHint.Position = UDim2.new(0, 20, 0, baseY)
	exitHint.Size = UDim2.new(0, 150, 0, 36)
	exitHint.BackgroundColor3 = Color3.fromRGB(20, 15, 18)
	exitHint.BackgroundTransparency = 0.35
	exitHint.BorderSizePixel = 0
	exitHint.Font = Enum.Font.SpecialElite
	exitHint.TextSize = 14
	exitHint.TextColor3 = Color3.fromRGB(220, 200, 190)
	exitHint.Text = isTouch() and "LEAVE STALL" or "[E] LEAVE STALL"
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

	-- BillboardGui di Attachment lubang pintu (state HIDDEN, bisa di-tap di mobile)
	local peekBillboard = playerGui:FindFirstChild("SafeZonePeekBillboard") or Instance.new("BillboardGui")
	peekBillboard.Name = "SafeZonePeekBillboard"
	peekBillboard.ResetOnSpawn = false
	peekBillboard.AlwaysOnTop = true
	peekBillboard.LightInfluence = 0
	peekBillboard.Size = UDim2.new(0, 190, 0, 32)
	peekBillboard.MaxDistance = 15
	peekBillboard.Active = true
	peekBillboard.Enabled = false
	peekBillboard.Parent = playerGui
	peekBillboard:ClearAllChildren()

	local billboardFrame = Instance.new("Frame")
	billboardFrame.Name = "Container"
	billboardFrame.Size = UDim2.fromScale(1, 1)
	billboardFrame.BackgroundColor3 = Color3.fromRGB(20, 15, 18)
	billboardFrame.BackgroundTransparency = 0.35
	billboardFrame.BorderSizePixel = 0
	billboardFrame.Parent = peekBillboard

	local billboardCorner = Instance.new("UICorner")
	billboardCorner.CornerRadius = UDim.new(0, 4)
	billboardCorner.Parent = billboardFrame

	local billboardStroke = Instance.new("UIStroke")
	billboardStroke.Color = Color3.fromRGB(80, 20, 25)
	billboardStroke.Thickness = 1
	billboardStroke.Transparency = 0.3
	billboardStroke.Parent = billboardFrame

	local billboardLabel = Instance.new("TextButton")
	billboardLabel.Name = "Button"
	billboardLabel.Size = UDim2.fromScale(1, 1)
	billboardLabel.BackgroundTransparency = 1
	billboardLabel.BorderSizePixel = 0
	billboardLabel.Font = Enum.Font.SpecialElite
	billboardLabel.TextSize = 14
	billboardLabel.TextColor3 = Color3.fromRGB(220, 200, 190)
	billboardLabel.Text = isTouch() and "PEEK THROUGH HOLE" or "[F] PEEK THROUGH HOLE"
	billboardLabel.AutoButtonColor = true
	billboardLabel.Parent = billboardFrame

	billboardLabel.MouseButton1Click:Connect(function()
		if self.active and self.state == "HIDDEN" then
			self:togglePeek()
		end
	end)

	-- Hint tombol [F] di ScreenGui (hanya tampil saat PEEKING, di bawah ExitHint)
	local peekHint = Instance.new("TextButton")
	peekHint.Name = "ScreenPeekHint"
	peekHint.AnchorPoint = Vector2.new(0, 0)
	peekHint.Position = UDim2.new(0, 20, 0, baseY + 42)
	peekHint.Size = UDim2.new(0, 150, 0, 36)
	peekHint.BackgroundColor3 = Color3.fromRGB(20, 15, 18)
	peekHint.BackgroundTransparency = 0.35
	peekHint.BorderSizePixel = 0
	peekHint.Font = Enum.Font.SpecialElite
	peekHint.TextSize = 14
	peekHint.TextColor3 = Color3.fromRGB(220, 200, 190)
	peekHint.Text = isTouch() and "STOP PEEKING" or "[F] STOP PEEKING"
	peekHint.AutoButtonColor = true
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

	peekHint.MouseButton1Click:Connect(function()
		self:togglePeek()
	end)

	self.gui = gui
	self.shade = shade
	self.exitHint = exitHint
	self.vignette = vignette
	self.peekHint = peekHint
	self.peekBillboard = peekBillboard
	self.billboardLabel = billboardLabel

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

function PeekCamera:_attach(peekCF: CFrame, hideCF: CFrame?, zonePart: BasePart?)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	self.savedType = cam.CameraType
	self.savedSubject = cam.CameraSubject
	self.savedMouse = UserInputService.MouseBehavior
	self.savedFOV = cam.FieldOfView

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

	-- Hubungkan Adornee Billboard ke marker Attachment / Part di pintu
	if self._tempMarker then
		self._tempMarker:Destroy()
		self._tempMarker = nil
	end

	-- Mainkan audio SafeZone (HeartBeat + BreathDeep) loop di client
	self:playSafeZoneAudio()

	local marker = zonePart and Anchors.peekMarker(zonePart)
	if not marker and typeof(peekCF) == "CFrame" then
		local tempAtt = Instance.new("Attachment")
		tempAtt.Name = "TempPeekMarker"
		tempAtt.WorldCFrame = peekCF
		tempAtt.Parent = (zonePart and zonePart:IsA("BasePart")) and zonePart or workspace.Terrain
		self._tempMarker = tempAtt
		marker = tempAtt
	end

	if self.peekBillboard then
		self.peekBillboard.Adornee = marker
	end

	-- Sembunyikan hotbar backpack bawaan agar ruang bawah layar bersih di HP/PC
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local touch = isTouch()
	if self.exitHint then
		self.exitHint.Text = touch and "LEAVE STALL" or "[E] LEAVE STALL"
	end
	if self.billboardLabel then
		self.billboardLabel.Text = touch and "PEEK THROUGH HOLE" or "[F] PEEK THROUGH HOLE"
	end
	if self.peekHint then
		self.peekHint.Text = touch and "STOP PEEKING" or "[F] STOP PEEKING"
	end

	-- Masuk = state HIDDEN: vignette gelap nyala, billboard [F] muncul
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
	local touch = isTouch()
	if isHidden then
		-- State HIDDEN: Billboard [F] di lubang aktif, hint screen mati
		if self.peekBillboard then
			self.peekBillboard.Enabled = true
		end
		if self.billboardLabel then
			self.billboardLabel.Text = touch and "PEEK THROUGH HOLE" or "[F] PEEK THROUGH HOLE"
		end
		if self.peekHint then
			self.peekHint.Visible = false
		end
	else
		-- State PEEKING: Billboard di lubang mati (pandangan bersih), hint screen [F] STOP aktif
		if self.peekBillboard then
			self.peekBillboard.Enabled = false
		end
		if self.peekHint then
			self.peekHint.Text = touch and "STOP PEEKING" or "[F] STOP PEEKING"
			self.peekHint.Visible = true
		end
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
		-- -> PEEKING: tween ke lubang pintu, FOV sempit fokus lubang (48)
		self.state = "PEEKING"
		self:_applyHiddenVisual(false)
		self:_tweenCameraTo(self.peekCF, 0.5, 48)
	else
		-- -> HIDDEN: tween balik ke posisi gelap, FOV normal
		self.state = "HIDDEN"
		self:_applyHiddenVisual(true)
		self:_tweenCameraTo(self.hideCF, 0.5, self.savedFOV or 70)
	end
end

--- Tween baseCF ke target selama `duration` detik. RenderStep loop membaca
--- baseCF tiap frame, jadi kita animasikan baseCF (bukan cam.CFrame langsung).
function PeekCamera:_tweenCameraTo(targetCF: CFrame, duration: number, targetFOV: number?)
	if not targetCF then
		return
	end
	local cam = workspace.CurrentCamera
	local fromCF = self.baseCF or targetCF
	local fromFOV = cam and cam.FieldOfView or 70
	local toFOV = targetFOV or fromFOV

	-- Reset lirikan supaya masuk ke posisi baru tanpa offset aneh
	self.yaw = 0
	self.pitch = 0

	local startTime = os.clock()
	local dur = math.max(0.05, duration)
	self._tweening = true

	task.spawn(function()
		while true do
			local alpha = math.clamp((os.clock() - startTime) / dur, 0, 1)
			-- Ease in-out quad
			local ease = alpha < 0.5 and 2 * alpha * alpha or 1 - ((-2 * alpha + 2) ^ 2) / 2
			self.baseCF = fromCF:Lerp(targetCF, ease)
			if cam then
				cam.FieldOfView = fromFOV + (toFOV - fromFOV) * ease
			end
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		self.baseCF = targetCF
		if cam then
			cam.FieldOfView = toFOV
		end
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

	if self.peekBillboard then
		self.peekBillboard.Enabled = false
		self.peekBillboard.Adornee = nil
	end

	if self._tempMarker then
		self._tempMarker:Destroy()
		self._tempMarker = nil
	end

	-- Pulihkan Hotbar Backpack bawaan
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)

	-- Hentikan audio SafeZone
	self:stopSafeZoneAudio()

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
		if self.savedFOV then
			cam.FieldOfView = self.savedFOV
		end
	end
	self.savedType, self.savedSubject, self.savedMouse, self.savedFOV = nil, nil, nil, nil
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
				self:_attach(peekCF, hideCF, payload.zone)
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
	if self.peekBillboard then
		self.peekBillboard.Enabled = false
		self.peekBillboard.Adornee = nil
	end
	if self._tempMarker then
		self._tempMarker:Destroy()
		self._tempMarker = nil
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
	self:stopSafeZoneAudio()
	if self.blur then
		self.blur.Size = 0
	end
	local cam = workspace.CurrentCamera
	if cam and self.savedFOV then
		cam.FieldOfView = self.savedFOV
	end
end

function PeekCamera:destroy()
	self:forceRelease()
	self:stopSafeZoneAudio()
	if self.gui then
		self.gui:Destroy()
	end
	if self.peekBillboard then
		self.peekBillboard:Destroy()
	end
	if self._tempMarker then
		self._tempMarker:Destroy()
	end
	if self.blur then
		self.blur:Destroy()
	end
	if self._audioContainer then
		self._audioContainer:Destroy()
	end
	self.gui = nil
	self.shade = nil
	self.exitHint = nil
	self.vignette = nil
	self.peekHint = nil
	self.peekBillboard = nil
	self.billboardLabel = nil
	self._tempMarker = nil
	self._audioContainer = nil
	self.blur = nil
end

---------------------------------------------------------------------
-- AUDIO SAFEZONE (Client-side loop)
---------------------------------------------------------------------

--- Mainkan HeartBeat & BreathDeep loop saat pemain masuk bilik.
function PeekCamera:playSafeZoneAudio()
	self:stopSafeZoneAudio() -- bersihkan sisa audio lama

	local audioRoot = ReplicatedStorage:FindFirstChild("Audio")
	local safeZoneAudio = audioRoot and audioRoot:FindFirstChild("SafeZone")
	if not safeZoneAudio then
		return
	end

	local container = Instance.new("Folder")
	container.Name = "SafeZoneAudio"
	container.Parent = self.player:FindFirstChildOfClass("PlayerGui") or self.player

	local heartbeat = safeZoneAudio:FindFirstChild("HeartBeat")
	local breath = safeZoneAudio:FindFirstChild("BreathDeep")

	if heartbeat and heartbeat:IsA("Sound") then
		local hb = heartbeat:Clone()
		hb.Name = "HeartBeat"
		hb.Looped = true
		hb.Volume = 0.5
		hb.Parent = container
		hb:Play()
	end

	if breath and breath:IsA("Sound") then
		local bd = breath:Clone()
		bd.Name = "BreathDeep"
		bd.Looped = true
		bd.Volume = 0.4
		bd.Parent = container
		bd:Play()
	end

	self._audioContainer = container
end

--- Hentikan dan bersihkan audio SafeZone.
function PeekCamera:stopSafeZoneAudio()
	if self._audioContainer then
		for _, child in self._audioContainer:GetChildren() do
			if child:IsA("Sound") then
				child:Stop()
			end
		end
		self._audioContainer:Destroy()
		self._audioContainer = nil
	end
end

return PeekCamera
