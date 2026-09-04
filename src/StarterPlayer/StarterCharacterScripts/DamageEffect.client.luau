--[[
	DamageEffect.client.luau  (StarterPlayer > StarterCharacterScripts)
	------------------------------------------------------------------
	Efek Horror Sinematik saat monster mendekat:
	  1. 4-Sisi Horror Vignette Darah: Gradien hitam & merah tua pekat di sekeliling
	     layar (tanpa gambar eksternal, 100% aman).
	  2. Heartbeat Pulse: Vignette berdenyut seirama detak jantung yang semakin
	     cepat saat monster makin dekat (< 14 studs).
	  3. Panic Camera Shake: Guncangan kamera procedural (math.noise) yang semakin
	     hebat saat monster mendekat.
	  4. Adrenaline Blur (`Lighting.BlurEffect`): Penglihatan mengabur saat monster
	     sangat dekat (< 9 studs) efek syok teror.
	  5. Jarak Adaptif: Mengkompensasi tinggi monster raksasa (Clown Y offset) agar
	     intensitas benar-benar mencapai 100% saat menempel.

	VERSATILE: Monster dicari otomatis lewat tag "Monster" (CollectionService).
	Mendukung banyak monster, monster terdekat yang masih hidup yang mengendalikan efek.
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
local START_DIST      = 22    -- jarak mulai terasa bayangan & getar halus (studs)
local PULSE_DIST      = 13    -- jarak mulai berdenyut jantung (studs)
local BLUR_DIST       = 8     -- jarak penglihatan mengabur (studs)

-- Shake dikalibrasi agar menegangkan tapi TIDAK pusing / mual:
-- Max shake 0.12 rad (~3.4 derajat), roll Z ditiadakan agar horizon stabil.
local MAX_SHAKE       = 0.11  -- guncangan maksimum halus (radians)
local SHAKE_SPEED     = 11    -- frekuensi getar mengalir (bukan bor getar)
local MAX_VIGNETTE    = 0.82  -- kepekatan maksimum vignette di tepi layar (0..1)
local MAX_BLUR        = 10    -- tingkat blur saat monster menempel
local SCAN_INTERVAL   = 0.1   -- detik; scan monster terdekat 10x/detik

local RENDER_NAME     = "SilencioHorrorCinematic"
local BLUR_NAME       = "SilencioHorrorAdrenalineBlur"
local GUI_NAME        = "SilencioHorrorVignetteGui"

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

-- 4 Sisi Gradien Gelap / Merah Darah Pekat
local function makeVigFrame(size, pos, rot, col, alphaStart)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = col
	f.BackgroundTransparency = 1 -- awal transparan
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

-- Flash tengah saat diserang / sangat dekat
local centerFlash = Instance.new("Frame")
centerFlash.Name = "CenterBloodFlash"
centerFlash.Size = UDim2.fromScale(1, 1)
centerFlash.BackgroundColor3 = Color3.fromRGB(110, 8, 15)
centerFlash.BackgroundTransparency = 1
centerFlash.BorderSizePixel = 0
centerFlash.Active = false
centerFlash.Parent = vignetteContainer

local vigFrames = { topVig, bottomVig, leftVig, rightVig }

-----------------------------------------------------------------
--- Hitung jarak efektif ke monster (kompensasi tinggi monster raksasa)
-----------------------------------------------------------------
local function effectiveDistance(playerPos: Vector3, monsterRoot: BasePart): number
	local mPos = monsterRoot.Position
	local horizontalDist = (Vector2.new(playerPos.X, playerPos.Z) - Vector2.new(mPos.X, mPos.Z)).Magnitude
	local verticalDiff = math.max(0, math.abs(playerPos.Y - mPos.Y) - 3.5)
	return math.sqrt(horizontalDist * horizontalDist + verticalDiff * verticalDiff)
end

--- Cari monster terdekat yang masih hidup
local function nearestMonsterRoot(fromPos: Vector3): (BasePart?, number)
	local bestRoot: BasePart? = nil
	local bestDist = math.huge

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

	return bestRoot, bestDist
end

-----------------------------------------------------------------
local tickWaktu = 0
local pulseTick = 0
local scanAccum = SCAN_INTERVAL
local monsterRoot: BasePart? = nil
local monsterDist = math.huge

local function onRender(dt: number)
	if not hrp or not hrp.Parent then
		for _, f in vigFrames do f.BackgroundTransparency = 1 end
		centerFlash.BackgroundTransparency = 1
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
		if blurEffect and blurEffect.Size > 0 then
			blurEffect.Size = math.max(0, blurEffect.Size - dt * 18)
		end
		return
	end

	-- 1. Intensitas dasar (0 saat START_DIST, 1 saat menempel 0)
	local intensity = math.clamp(1 - (monsterDist / START_DIST), 0, 1)

	-- 2. Heartbeat Denyut saat monster dekat (< PULSE_DIST)
	local pulseMultiplier = 1
	if monsterDist < PULSE_DIST then
		local pulseSpeed = 7 + (1 - (monsterDist / PULSE_DIST)) * 11 -- 7 hingga 18 rad/detik
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

	-- 4. Center Flash kemerahan saat monster menempel (< 6 studs)
	if monsterDist < 6 then
		local flashInt = (6 - monsterDist) / 6
		centerFlash.BackgroundTransparency = 1 - (flashInt * 0.35 * pulseMultiplier)
	else
		centerFlash.BackgroundTransparency = 1
	end

	-- 5. Adrenaline Blur (Lighting.BlurEffect) saat monster < BLUR_DIST
	if blurEffect then
		if monsterDist < BLUR_DIST then
			local blurInt = (BLUR_DIST - monsterDist) / BLUR_DIST
			blurEffect.Size = math.floor(blurInt * MAX_BLUR)
		else
			blurEffect.Size = math.max(0, blurEffect.Size - dt * 20)
		end
	end

	-- 6. Camera Shake Procedural Halus (Bebas Pusing/Motion Sickness)
	-- Roll Z ditiadakan agar garis horizon tetap lurus stabil.
	-- Jitter hanya di Pitch (naik-turun) dan Yaw (lirik mikro).
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
	if blurEffect then
		blurEffect.Size = 0
	end
end

cleanup()

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)

local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
	humanoid.Died:Connect(cleanup)
end

character.AncestryChanged:Connect(function(_, parent)
	if not parent then
		cleanup()
	end
end)
