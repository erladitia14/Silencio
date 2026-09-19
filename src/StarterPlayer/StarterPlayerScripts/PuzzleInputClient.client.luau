--!strict
--[[
	PuzzleInputClient — input & feedback client untuk puzzle baterai/assembly.

	Tugas:
	1. Tombol SIMPAN (Q): kirim ke server untuk menaruh item yang sedang dibawa
	   (baterai maupun engine/panel). Server yang memutuskan valid/tidak.
	2. Tampilkan WARNING singkat di tengah-bawah layar (mis. "Pasang Engine dulu")
	   saat server mengirim PuzzleWarnEvent.

	Tidak menyentuh sistem lain; murni input + UI feedback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local storeEvent = ReplicatedStorage:WaitForChild("PuzzleStoreEvent")
local warnEvent = ReplicatedStorage:WaitForChild("PuzzleWarnEvent")

local STORE_KEY = Enum.KeyCode.Q

-- ----------------------------------------------------------------------
-- UI: satu label warning + satu hint "Q simpan"
-- ----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "PuzzleFeedbackGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Warning (tengah-bawah, merah, auto-hilang)
local warnLabel = Instance.new("TextLabel")
warnLabel.Name = "Warning"
warnLabel.AnchorPoint = Vector2.new(0.5, 1)
warnLabel.Position = UDim2.new(0.5, 0, 0.82, 0)
warnLabel.Size = UDim2.new(0, 520, 0, 44)
warnLabel.BackgroundTransparency = 0.25
warnLabel.BackgroundColor3 = Color3.fromRGB(30, 0, 0)
warnLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
warnLabel.Font = Enum.Font.GothamBold
warnLabel.TextScaled = true
warnLabel.Text = ""
warnLabel.Visible = false
warnLabel.ZIndex = 10
warnLabel.Parent = gui

local warnPad = Instance.new("UIPadding")
warnPad.PaddingLeft = UDim.new(0, 14)
warnPad.PaddingRight = UDim.new(0, 14)
warnPad.Parent = warnLabel

local warnCorner = Instance.new("UICorner")
warnCorner.CornerRadius = UDim.new(0, 8)
warnCorner.Parent = warnLabel

-- Hint "Q simpan" (kanan-bawah, muncul saat sedang membawa item)
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "StoreHint"
hintLabel.AnchorPoint = Vector2.new(1, 1)
hintLabel.Position = UDim2.new(1, -20, 1, -20)
hintLabel.Size = UDim2.new(0, 210, 0, 34)
hintLabel.BackgroundTransparency = 0.35
hintLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
hintLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextScaled = true
hintLabel.Text = "[Q] Simpan barang"
hintLabel.Visible = false
hintLabel.ZIndex = 10
hintLabel.Parent = gui

local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft = UDim.new(0, 10)
hintPad.PaddingRight = UDim.new(0, 10)
hintPad.Parent = hintLabel

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 6)
hintCorner.Parent = hintLabel

-- ----------------------------------------------------------------------
-- Warning handler
-- ----------------------------------------------------------------------

local warnToken = 0
warnEvent.OnClientEvent:Connect(function(message: string)
	warnToken += 1
	local myToken = warnToken
	warnLabel.Text = tostring(message)
	warnLabel.Visible = true
	task.delay(2.5, function()
		if myToken == warnToken then
			warnLabel.Visible = false
		end
	end)
end)

-- ----------------------------------------------------------------------
-- Hint "Q simpan": tampil kalau Character sedang membawa item
-- (dibaca dari Attribute yang di-set service: CarryingBattery / CarryingAssemblyPart)
-- ----------------------------------------------------------------------

local function isCarrying(): boolean
	local char = player.Character
	if not char then return false end
	local bat = char:GetAttribute("CarryingBattery")
	local asm = char:GetAttribute("CarryingAssemblyPart")
	return (bat == true) or (asm ~= nil and asm ~= false)
end

task.spawn(function()
	while true do
		hintLabel.Visible = isCarrying()
		task.wait(0.2)
	end
end)

-- ----------------------------------------------------------------------
-- Input: Q untuk simpan
-- ----------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == STORE_KEY then
		if isCarrying() then
			storeEvent:FireServer()
		end
	end
end)
