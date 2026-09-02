--[[
	DamageEffect.client.luau  (StarterPlayer > StarterCharacterScripts)
	------------------------------------------------------------------
	Efek horror saat monster mendekat: vignette merah + camera shake.
	Makin dekat monster, makin pekat merahnya dan makin kencang getarnya.

	VERSATILE: monster dicari lewat tag "Monster" (CollectionService),
	BUKAN nama objek. Jadi berapa pun jumlah monster, apa pun namanya, dan
	di mana pun letaknya di Workspace, efek ini tetap jalan tanpa diedit.
	Yang dipakai = monster TERDEKAT yang masih hidup.

	Ini LocalScript (client) karena menyentuh Camera & GUI — dua hal yang
	memang milik client. Tidak ada logika game di sini, murni presentasi.

	CATATAN: ini file mandiri. Tidak me-require modul KeySystem maupun
	EnemyController, dan tidak ada modul yang bergantung padanya.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-----------------------------------------------------------------
-- SETELAN (ubah di sini)
-----------------------------------------------------------------
local MONSTER_TAG   = "Monster"
local START_DIST    = 20    -- jarak mulai terasa (stud)
local MAX_SHAKE     = 0.4   -- amplitudo getar; noise -0.5..0.5 -> maks ~11.5 deg
local SHAKE_SPEED   = 18    -- kecepatan getar
local MAX_VIGNETTE  = 0.5   -- kepekatan merah maksimum (0..1)
local SCAN_INTERVAL = 0.1   -- detik; cari monster terdekat 10x/detik

local RENDER_NAME = "SilencioHorrorShake"

-----------------------------------------------------------------
local player = Players.LocalPlayer
local character = script.Parent
local hrp = character:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")

-- GUI dipakai ulang kalau sudah ada, supaya respawn tidak menumpuk
-- ScreenGui baru di PlayerGui.
local horrorGui = playerGui:FindFirstChild("HorrorVignette")
if not horrorGui then
	horrorGui = Instance.new("ScreenGui")
	horrorGui.Name = "HorrorVignette"
	horrorGui.IgnoreGuiInset = true
	horrorGui.ResetOnSpawn = false -- dikelola script ini, jangan dihapus engine
	horrorGui.Parent = playerGui
end

local redFrame = horrorGui:FindFirstChild("RedFlash")
if not redFrame then
	redFrame = Instance.new("Frame")
	redFrame.Name = "RedFlash"
	redFrame.Size = UDim2.new(1, 0, 1, 0)
	redFrame.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
	redFrame.BorderSizePixel = 0
	redFrame.ZIndex = 10
	redFrame.Active = false -- jangan blokir klik/tap pemain
	redFrame.Parent = horrorGui
end
redFrame.BackgroundTransparency = 1

-----------------------------------------------------------------
--- Cari root monster TERDEKAT yang masih hidup. Monster mati dilewati
--- supaya bangkai tidak terus memicu efek.
local function nearestMonsterRoot(fromPos: Vector3): (BasePart?, number)
	local bestRoot: BasePart? = nil
	local bestDist = math.huge

	for _, monster in CollectionService:GetTagged(MONSTER_TAG) do
		if monster:IsA("Model") and monster.Parent then
			local root = monster:FindFirstChild("HumanoidRootPart") or monster.PrimaryPart
			local humanoid = monster:FindFirstChildOfClass("Humanoid")
			-- Humanoid tidak wajib; kalau ada, hormati Health.
			if root and root:IsA("BasePart") and (not humanoid or humanoid.Health > 0) then
				local d = (fromPos - root.Position).Magnitude
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
local scanAccum = SCAN_INTERVAL -- biar scan jalan di frame pertama
local monsterRoot: BasePart? = nil
local monsterDist = math.huge

local function onRender(dt: number)
	-- Karakter sudah lepas dari Workspace (mati/respawn): jangan kerja.
	if not hrp.Parent then
		redFrame.BackgroundTransparency = 1
		return
	end

	tickWaktu += dt * SHAKE_SPEED
	scanAccum += dt

	if scanAccum >= SCAN_INTERVAL then
		-- Scan penuh: 10x/detik cukup, jarak tidak berubah signifikan
		-- dalam 100 ms dan ini jauh lebih murah daripada tiap frame.
		scanAccum = 0
		monsterRoot, monsterDist = nearestMonsterRoot(hrp.Position)
	elseif monsterRoot and monsterRoot.Parent then
		-- Di antara scan: cukup segarkan jarak monster yang sama (murah),
		-- supaya intensitas tetap mulus mengikuti gerak pemain.
		monsterDist = (hrp.Position - monsterRoot.Position).Magnitude
	end

	if not monsterRoot or not monsterRoot.Parent or monsterDist > START_DIST then
		redFrame.BackgroundTransparency = 1
		return
	end

	local intensity = 1 - (monsterDist / START_DIST)
	redFrame.BackgroundTransparency = 1 - (intensity * MAX_VIGNETTE)

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Getaran ditumpuk SETELAH camera module menulis CFrame-nya (lihat
	-- RenderPriority di bawah), jadi tidak berebut dengan kontrol kamera.
	local shakeAmount = MAX_SHAKE * intensity
	camera.CFrame = camera.CFrame
		* CFrame.Angles(
			math.noise(tickWaktu, 0, 0) * shakeAmount,
			math.noise(0, tickWaktu, 0) * shakeAmount,
			math.noise(0, 0, tickWaktu) * shakeAmount
		)
end

-----------------------------------------------------------------
local function cleanup()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	redFrame.BackgroundTransparency = 1
end

-- Lepas bind lama kalau masih tersisa (respawn cepat / Play ulang).
cleanup()

-- Camera.Value + 1 = jalan SETELAH camera module Roblox menulis CFrame.
-- Pakai RenderStepped biasa, urutannya tidak dijamin dan getaran bisa
-- ditimpa camera module di frame yang sama.
RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)

-- Bersihkan saat karakter mati atau dihapus, supaya bind tidak menumpuk
-- dan tidak memegang referensi ke karakter lama.
local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
	humanoid.Died:Connect(cleanup)
end

character.AncestryChanged:Connect(function(_, parent)
	if not parent then
		cleanup()
	end
end)
