--[[
	DamageEffect.client.luau  (StarterPlayer > StarterCharacterScripts)
	------------------------------------------------------------------
	Efek Horror Sinematik saat monster mendekat:
	  1. 4-Sisi Horror Vignette Darah
	  2. UiDikejar (Dengung & bcak overlay dengan IgnoreGuiInset untuk HP/Mobile)
	  3. Heartbeat Pulse & Panic Camera Shake
	  4. Adrenaline Blur (`Lighting.BlurEffect`)
--]]

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

-----------------------------------------------------------------
-- SETELAN (tuning efek horor)
-----------------------------------------------------------------
local MONSTER_TAG     = "Monster"
local START_DIST      = 15    -- jarak mulai terasa bayangan & getar (UiDikejar dipicu damage, bukan jarak)
local PULSE_DIST      = 12    -- jarak mulai berdenyut jantung (studs)
local BLUR_DIST       = 8     -- jarak penglihatan mengabur (studs)

local MAX_SHAKE       = 0.11  -- guncangan maksimum halus (radians)
local SHAKE_SPEED     = 11    -- frekuensi getar mengalir
local MAX_VIGNETTE    = 0.82  -- kepekatan maksimum vignette
local MAX_BLUR        = 10    -- tingkat blur saat monster menempel
local SCAN_INTERVAL   = 0.1   -- detik; scan monster terdekat 10x/detik

local RENDER_NAME     = "SilencioHorrorCinematic"
local BLUR_NAME       = "SilencioHorrorAdrenalineBlur"
local GUI_NAME        = "SilencioHorrorVignetteGui"
local UI_DIKEJAR_NAME = "UiDikejar"

-----------------------------------------------------------------
local player = Players.LocalPlayer
local character = script.Parent
local hrp = character:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")

-- 1. Setup Blur Effect di Lighting
local blurEffect = Lighting:FindFirstChild(BLUR_NAME)
if not blurEffect or not blurEffect:IsA("BlurEffect") then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = BLUR_NAME
	blurEffect.Size = 0
	blurEffect.Enabled = true
	blurEffect.Parent = Lighting
end

-- 2. Setup Horror Vignette ScreenGui
local horrorGui = playerGui:FindFirstChild(GUI_NAME)
if not horrorGui then
	horrorGui = Instance.new("ScreenGui")
	horrorGui.Name = GUI_NAME
	horrorGui.IgnoreGuiInset = true
	pcall(function()
		horrorGui.ScreenInsets = Enum.ScreenInsets.None
		horrorGui.ClipToDeviceSafeArea = false
	end)
	horrorGui.ResetOnSpawn = false
	horrorGui.DisplayOrder = 10
	horrorGui.Parent = playerGui
end
horrorGui:ClearAllChildren()

local vignetteContainer = Instance.new("Frame")
vignetteContainer.Name = "VignetteContainer"
vignetteContainer.Size = UDim2.fromScale(1, 1)
vignetteContainer.BackgroundTransparency = 1
vignetteContainer.Active = false
vignetteContainer.Parent = horrorGui

local function makeVigFrame(size, pos, rot, col, alphaStart)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = col
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.Parent = vignetteContainer

	local grad = Instance.new("UIGradient")
	grad.Rotation = rot
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, alphaStart),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = f
	return f
end

local topVig = makeVigFrame(UDim2.new(1, 0, 0.38, 0), UDim2.new(0, 0, 0, 0), 90, Color3.fromRGB(35, 0, 5), 0.1)
local bottomVig = makeVigFrame(UDim2.new(1, 0, 0.45, 0), UDim2.new(0, 0, 0.55, 0), -90, Color3.fromRGB(45, 0, 8), 0.05)
local leftVig = makeVigFrame(UDim2.new(0.32, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0, Color3.fromRGB(30, 0, 4), 0.15)
local rightVig = makeVigFrame(UDim2.new(0.32, 0, 1, 0), UDim2.new(0.68, 0, 0, 0), 180, Color3.fromRGB(30, 0, 4), 0.15)

local centerFlash = Instance.new("Frame")
centerFlash.Name = "CenterBloodFlash"
centerFlash.Size = UDim2.fromScale(1, 1)
centerFlash.BackgroundColor3 = Color3.fromRGB(110, 8, 15)
centerFlash.BackgroundTransparency = 1
centerFlash.BorderSizePixel = 0
centerFlash.Active = false
centerFlash.Parent = vignetteContainer

local vigFrames = { topVig, bottomVig, leftVig, rightVig }

-- 3. Setup UiDikejar (Horror Chase Overlay dengan IgnoreGuiInset untuk HP/Mobile)
local uiDikejar = playerGui:FindFirstChild(UI_DIKEJAR_NAME) :: ScreenGui?
if not uiDikejar then
	uiDikejar = Instance.new("ScreenGui")
	uiDikejar.Name = UI_DIKEJAR_NAME
	uiDikejar.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	uiDikejar.Parent = playerGui
end
uiDikejar.IgnoreGuiInset = true -- Pas di HP & menembus safe area limit
uiDikejar.DisplayOrder = 20
uiDikejar.ResetOnSpawn = false
pcall(function()
	uiDikejar.ScreenInsets = Enum.ScreenInsets.None
	uiDikejar.ClipToDeviceSafeArea = false
end)

local frameDikejar = uiDikejar:FindFirstChild("Frame") :: Frame?
if not frameDikejar then
	frameDikejar = Instance.new("Frame")
	frameDikejar.Name = "Frame"
	frameDikejar.AnchorPoint = Vector2.new(0.5, 0.5)
	frameDikejar.Position = UDim2.new(0.5, 0, 0.5, 0)
	frameDikejar.Size = UDim2.new(1, 0, 1, 0)
	frameDikejar.BackgroundColor3 = Color3.new(0, 0, 0)
	frameDikejar.BackgroundTransparency = 1
	frameDikejar.BorderSizePixel = 0
	frameDikejar.Active = false
	frameDikejar.Parent = uiDikejar
end

local dengungFrame = frameDikejar:FindFirstChild("Dengung") :: Frame?
if not dengungFrame then
	dengungFrame = Instance.new("Frame")
	dengungFrame.Name = "Dengung"
	dengungFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	dengungFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	dengungFrame.Size = UDim2.new(1.02, 0, 1.01, 0)
	dengungFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	dengungFrame.BackgroundTransparency = 1
	dengungFrame.BorderSizePixel = 0
	dengungFrame.Active = false
	dengungFrame.Parent = frameDikejar
end

local dengungImg = dengungFrame:FindFirstChildOfClass("ImageLabel") :: ImageLabel?
if not dengungImg then
	dengungImg = Instance.new("ImageLabel")
	dengungImg.Name = "ImageLabel"
	dengungImg.AnchorPoint = Vector2.new(0.5, 0.5)
	dengungImg.Position = UDim2.new(0.49, 0, 0.49, 0)
	dengungImg.Size = UDim2.new(1.04, 0, 0.99, 0)
	dengungImg.BackgroundColor3 = Color3.new(1, 1, 1)
	dengungImg.BackgroundTransparency = 1
	dengungImg.BorderSizePixel = 0
	dengungImg.Image = "rbxassetid://138268408438368"
	dengungImg.ImageTransparency = 1
	dengungImg.Active = false
	dengungImg.Parent = dengungFrame
end

local bcakFrame = frameDikejar:FindFirstChild("bcak") :: Frame?
if not bcakFrame then
	bcakFrame = Instance.new("Frame")
	bcakFrame.Name = "bcak"
	bcakFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	bcakFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	bcakFrame.Size = UDim2.new(1.02, 0, 1.01, 0)
	bcakFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	bcakFrame.BackgroundTransparency = 1
	bcakFrame.BorderSizePixel = 0
	bcakFrame.Active = false
	bcakFrame.Parent = frameDikejar
end

local bcakImg = bcakFrame:FindFirstChildOfClass("ImageLabel") :: ImageLabel?
if not bcakImg then
	bcakImg = Instance.new("ImageLabel")
	bcakImg.Name = "ImageLabel_1"
	bcakImg.AnchorPoint = Vector2.new(0.5, 0.5)
	bcakImg.Position = UDim2.new(0.5, 0, 0.5, 0)
	bcakImg.Size = UDim2.new(1, 0, 1, 0)
	bcakImg.BackgroundColor3 = Color3.new(1, 1, 1)
	bcakImg.BackgroundTransparency = 1
	bcakImg.BorderSizePixel = 0
	bcakImg.Image = "rbxassetid://76314301279241"
	bcakImg.ImageTransparency = 1
	bcakImg.Active = false
	bcakImg.Parent = bcakFrame
end

-- Awalnya nonaktifkan sampai monster terdeteksi mendekat
uiDikejar.Enabled = false

-----------------------------------------------------------------
local function effectiveDistance(playerPos: Vector3, monsterRoot: BasePart): number
	local mPos = monsterRoot.Position
	local horizontalDist = (Vector2.new(playerPos.X, playerPos.Z) - Vector2.new(mPos.X, mPos.Z)).Magnitude
	local verticalDiff = math.max(0, math.abs(playerPos.Y - mPos.Y) - 3.5)
	return math.sqrt(horizontalDist * horizontalDist + verticalDiff * verticalDiff)
end

local function nearestMonsterRoot(fromPos: Vector3): (BasePart?, number)
	local bestRoot: BasePart? = nil
	local bestDist = math.huge

	-- 1. Scan semua entitas bertag "Monster"
	for _, monster in CollectionService:GetTagged(MONSTER_TAG) do
		if monster:IsA("Model") and monster.Parent then
			local root = monster:FindFirstChild("HumanoidRootPart") or monster.PrimaryPart
			local humanoid = monster:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and (not humanoid or humanoid.Health > 0) then
				local d = effectiveDistance(fromPos, root)
				if d < bestDist then
					bestDist = d
					bestRoot = root
				end
			end
		end
	end

	-- 2. Fallback scan jika tag belum sempat tereplikasi ke client
	if not bestRoot then
		for _, name in ipairs({ "Clown_Phase1", "Clown", "Monster" }) do
			local m = Workspace:FindFirstChild(name)
			if m and m:IsA("Model") then
				local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				local humanoid = m:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and (not humanoid or humanoid.Health > 0) then
					local d = effectiveDistance(fromPos, root)
					if d < bestDist then
						bestDist = d
						bestRoot = root
					end
				end
			end
		end
	end

	return bestRoot, bestDist
end

-----------------------------------------------------------------
-----------------------------------------------------------------
-- UI DAMAGE: hanya nyala kalau player BENAR-BENAR kena hit
-----------------------------------------------------------------
-- Pemicu UI damage = Humanoid.Health TURUN (kena hit monster), BUKAN jarak.
-- Sebelumnya overlay UiDikejar nyala hanya karena monster < START_DIST,
-- sehingga player yang cuma dilewati / didekati monster (mis. Clown lewat
-- di jalur patroli waypoint-nya) tetap melihat UI damage walau HP penuh.
local HIT_UI_DURATION = 2.5   -- detik; UI damage tampil setelah kena hit
local lastHitTime = -math.huge
local lastHealth: number? = nil


local tickWaktu = 0
local pulseTick = 0
local scanAccum = SCAN_INTERVAL
local monsterRoot: BasePart? = nil
local monsterDist = math.huge

-- UI DAMAGE: nyala HANYA saat player benar-benar kena hit (Health turun).
-- Dipanggil SEBELUM early-return "di luar jangkauan horor" supaya tetap
-- jalan walau tidak ada monster di dekat player.
local function applyDamageUI(dt: number, pulseMultiplier: number)
	local hitRecent = (os.clock() - lastHitTime) < HIT_UI_DURATION
	if not hitRecent then
		if frameDikejar.BackgroundTransparency < 1 then
			frameDikejar.BackgroundTransparency = math.min(1, frameDikejar.BackgroundTransparency + dt * 2.5)
		end
		if dengungImg.ImageTransparency < 1 then
			dengungImg.ImageTransparency = math.min(1, dengungImg.ImageTransparency + dt * 2.5)
		end
		if bcakImg.ImageTransparency < 1 then
			bcakImg.ImageTransparency = math.min(1, bcakImg.ImageTransparency + dt * 2.5)
		end
		if centerFlash.BackgroundTransparency < 1 then
			centerFlash.BackgroundTransparency = math.min(1, centerFlash.BackgroundTransparency + dt * 3)
		end
		if uiDikejar and uiDikejar.Enabled
			and frameDikejar.BackgroundTransparency >= 0.99
			and dengungImg.ImageTransparency >= 0.99
			and bcakImg.ImageTransparency >= 0.99 then
			uiDikejar.Enabled = false
		end
		return
	end

	-- 1 tepat saat kena hit -> 0 saat durasi habis (UI meredup sendiri)
	local hitVis = math.clamp(1 - ((os.clock() - lastHitTime) / HIT_UI_DURATION), 0, 1)

	if uiDikejar and not uiDikejar.Enabled then
		uiDikejar.Enabled = true
	end

	local chaseVis = math.clamp(0.35 + (hitVis * 0.65), 0, 1)
	local targetFrameBg = 1 - (chaseVis * (1 - 0.85) * math.min(1.1, pulseMultiplier))
	local targetDengung = 1 - (chaseVis * (1 - 0.50) * math.min(1.1, pulseMultiplier))
	local targetBcak    = 1 - (chaseVis * (1 - 0.50) * math.min(1.1, pulseMultiplier))

	frameDikejar.BackgroundTransparency = math.clamp(targetFrameBg, 0.80, 1)
	dengungImg.ImageTransparency = math.clamp(targetDengung, 0.45, 1)
	bcakImg.ImageTransparency = math.clamp(targetBcak, 0.45, 1)

	centerFlash.BackgroundTransparency = 1 - (hitVis * 0.35 * pulseMultiplier)
end


local function onRender(dt: number)
	if not hrp or not hrp.Parent then
		for _, f in vigFrames do f.BackgroundTransparency = 1 end
		centerFlash.BackgroundTransparency = 1
		frameDikejar.BackgroundTransparency = 1
		dengungImg.ImageTransparency = 1
		bcakImg.ImageTransparency = 1
		if blurEffect then blurEffect.Size = 0 end
		return
	end

	tickWaktu += dt * SHAKE_SPEED
	scanAccum += dt

	if scanAccum >= SCAN_INTERVAL then
		scanAccum = 0
		monsterRoot, monsterDist = nearestMonsterRoot(hrp.Position)
	elseif monsterRoot and monsterRoot.Parent then
		monsterDist = effectiveDistance(hrp.Position, monsterRoot)
	end

	-- Hitung denyut untuk UI damage (independen dari jarak monster)
	local hitPulse = 1
	if monsterDist and monsterDist < PULSE_DIST then
		hitPulse = 0.82 + math.abs(math.sin(tickWaktu)) * 0.36
	end
	applyDamageUI(dt, hitPulse)


	-- Di luar jangkauan horor -> bersihkan efek
	if not monsterRoot or not monsterRoot.Parent or monsterDist > START_DIST then
		for _, f in vigFrames do
			if f.BackgroundTransparency < 1 then
				f.BackgroundTransparency = math.min(1, f.BackgroundTransparency + dt * 2.5)
			end
		end
		if centerFlash.BackgroundTransparency < 1 then
			centerFlash.BackgroundTransparency = math.min(1, centerFlash.BackgroundTransparency + dt * 3)
		end
		if frameDikejar.BackgroundTransparency < 1 then
			frameDikejar.BackgroundTransparency = math.min(1, frameDikejar.BackgroundTransparency + dt * 2.5)
		end
		if dengungImg.ImageTransparency < 1 then
			dengungImg.ImageTransparency = math.min(1, dengungImg.ImageTransparency + dt * 2.5)
		end
		if bcakImg.ImageTransparency < 1 then
			bcakImg.ImageTransparency = math.min(1, bcakImg.ImageTransparency + dt * 2.5)
		end
		if blurEffect and blurEffect.Size > 0 then
			blurEffect.Size = math.max(0, blurEffect.Size - dt * 18)
		end
		if uiDikejar and uiDikejar.Enabled and frameDikejar.BackgroundTransparency >= 0.99 and dengungImg.ImageTransparency >= 0.99 and bcakImg.ImageTransparency >= 0.99 then
			uiDikejar.Enabled = false
		end
		return
	end

	-- 1. Intensitas dasar (0 saat START_DIST, 1 saat menempel 0)
	local intensity = math.clamp(1 - (monsterDist / START_DIST), 0, 1)

	-- 2. Heartbeat Denyut saat monster dekat (< PULSE_DIST)
	local pulseMultiplier = 1
	if monsterDist < PULSE_DIST then
		local pulseSpeed = 7 + (1 - (monsterDist / PULSE_DIST)) * 11
		pulseTick += dt * pulseSpeed
		pulseMultiplier = 0.82 + math.abs(math.sin(pulseTick)) * 0.36
	else
		pulseTick = 0
	end

	-- 3. Aplikasikan Vignette Horor di 4 Sisi
	local targetVigAlpha = 1 - math.clamp(intensity * MAX_VIGNETTE * pulseMultiplier, 0, 0.96)
	for _, f in vigFrames do
		f.BackgroundTransparency = targetVigAlpha
	end

	-- 6. Adrenaline Blur (Lighting.BlurEffect) saat monster < BLUR_DIST
	if blurEffect then
		if monsterDist < BLUR_DIST then
			local blurInt = (BLUR_DIST - monsterDist) / BLUR_DIST
			blurEffect.Size = math.floor(blurInt * MAX_BLUR)
		else
			blurEffect.Size = math.max(0, blurEffect.Size - dt * 20)
		end
	end

	-- 7. Camera Shake Procedural Halus
	local camera = workspace.CurrentCamera
	if camera then
		local shakeAmount = MAX_SHAKE * (intensity ^ 1.5) * math.min(1.15, pulseMultiplier)
		local pitchShake = math.noise(tickWaktu, 0, 0) * shakeAmount
		local yawShake   = math.noise(0, tickWaktu, 0) * (shakeAmount * 0.8)
		camera.CFrame = camera.CFrame * CFrame.Angles(pitchShake, yawShake, 0)
	end
end

-----------------------------------------------------------------
local function cleanup()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	for _, f in vigFrames do
		f.BackgroundTransparency = 1
	end
	centerFlash.BackgroundTransparency = 1
	frameDikejar.BackgroundTransparency = 1
	dengungImg.ImageTransparency = 1
	bcakImg.ImageTransparency = 1
	if uiDikejar then
		uiDikejar.Enabled = false
	end
	if blurEffect then
		blurEffect.Size = 0
	end
end

cleanup()

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)

local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
	-- Deteksi kena hit: Health turun -> nyalakan UI damage sebentar.
	lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health: number)
		if lastHealth ~= nil and health < lastHealth then
			lastHitTime = os.clock()
		end
		lastHealth = health
	end)

	humanoid.Died:Connect(cleanup)
end

character.AncestryChanged:Connect(function(_, parent)
	if not parent then
		cleanup()
	end
end)
