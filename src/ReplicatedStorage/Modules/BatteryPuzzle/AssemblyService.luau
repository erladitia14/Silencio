--!strict
--[[
	AssemblyService — perakitan fisik genset (Engine + 2 Panel)
	Pola: sama persis BatteryService/CaseService, NOL koordinat hardcode.

	Konvensi tag:
	- "AssemblySlot"   -> BasePart placeholder di dalam Model Generator
	                      Attribute: Kind = "Engine" | "Panel"
	- "AssemblyPickup" -> BasePart yang diambil pemain di ruangan
	                      Attribute: Kind = "Engine" | "Panel"

	Alur:
	1. Game jalan: semua slot placeholder disembunyikan (Transparency = 1).
	2. Pemain ambil part (pickup) -> di-weld ke tangan, walkspeed turun (berat).
	3. Prompt install di slot HANYA nyala kalau:
	   - Pemain membawa part dengan Kind yang COCOK
	   - Untuk Panel: Engine HARUS sudah terpasang duluan (gating urutan)
	   - Hanya slot kosong yang prompt-nya aktif
	4. Tahan prompt 2 detik -> part di tangan Destroy(), slot placeholder muncul (Transparency = 0).
	5. 3/3 terpasang -> Generator Model diberi Attribute "GeneratorAssembled" = true.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)
local CarryAnimator = require(script.Parent.CarryAnimator)

local AssemblyService = {}

-- State
local carriedPart: { [Player]: BasePart } = {}
local carriedKind: { [Player]: string } = {}
local carrierSide: { [Player]: "Left" | "Right" } = {}
local engineCarriers: { [BasePart]: { left: Player?, right: Player? } } = {}
local savedSpeed: { [Player]: { walk: number, jump: number, autoRotate: boolean } } = {}
local engineLockRuntimes: { [BasePart]: {
	conn: RBXScriptConnection?,
	offsets: {[Player]: CFrame},
	driver: Player?,
	lockedRotation: CFrame?,
} } = {}

-- Registrasi slot & pickup
type SlotRecord = {
	part: BasePart,
	kind: string,
	filled: boolean,
	prompt: ProximityPrompt,
}
local slots: { [BasePart]: SlotRecord } = {}
local pickups: { [BasePart]: { kind: string, prompt: ProximityPrompt, homeCF: CFrame, helpPrompt: ProximityPrompt?, attachments: {left: Attachment?, right: Attachment?} } } = {}

-- Model generator pemilik (dideteksi dari parent slot)
local generatorModel: Model? = nil

local onAssembledCallback: ((genModel: Model) -> ())? = nil
local onWarnCallback: ((player: Player, message: string) -> ())? = nil
local onCarryChanged: (() -> ())? = nil
local isBatteryCarrying: (() -> boolean)? = nil

function AssemblyService.setWarnCallback(cb: (player: Player, message: string) -> ())
	onWarnCallback = cb
end

function AssemblyService.setCarryChangedCallback(cb: () -> ())
	onCarryChanged = cb
end

function AssemblyService.setBatteryCarryingChecker(fn: () -> boolean)
	isBatteryCarrying = fn
end

function AssemblyService.isAnyoneCarrying(): boolean
	for _ in pairs(carriedPart) do
		return true
	end
	return false
end

local function warn_(player: Player, message: string)
	if onWarnCallback then
		onWarnCallback(player, message)
	end
end

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------

local function getHand(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	return (char:FindFirstChild("RightHand")
		or char:FindFirstChild("Right Arm")
		or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function isEngineInstalled(): boolean
	for _, rec in pairs(slots) do
		if rec.kind == "Engine" and rec.filled then
			return true
		end
	end
	return false
end

local function countFilled(): (number, number)
	local filled, total = 0, 0
	for _, rec in pairs(slots) do
		total += 1
		if rec.filled then filled += 1 end
	end
	return filled, total
end

-- ----------------------------------------------------------------------
-- Refresh Prompts (Inti Gating)
-- ----------------------------------------------------------------------

local isRefreshing = false
function AssemblyService.refreshPrompts()
	if isRefreshing then return end
	isRefreshing = true

	local anyCarrying = false
	for _ in pairs(carriedPart) do
		anyCarrying = true
		break
	end

	-- Juga cek apakah ada pemain yang sedang membawa baterai
	if not anyCarrying and isBatteryCarrying and isBatteryCarrying() then
		anyCarrying = true
	end

	if not anyCarrying then
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char and char:GetAttribute(Config.CarryingAttribute) == true then
				anyCarrying = true
				break
			end
		end
	end

	-- 1. Refresh prompt pickup & help carry:
	-- Jika ada pemain yang sedang bawa part assembly / baterai, matikan semua pickup lain.
	for part, info in pairs(pickups) do
		if part.Parent == nil then
			pickups[part] = nil
		elseif anyCarrying then
			info.prompt.Enabled = false
			-- Jika part ini adalah Engine yang sedang dibawa tepat 1 orang, nyalakan prompt Help Carry
			local ec = engineCarriers[part]
			if info.helpPrompt then
				local isSoloEngine = ec and ((ec.left ~= nil and ec.right == nil) or (ec.left == nil and ec.right ~= nil))
				info.helpPrompt.Enabled = (isSoloEngine == true)
			end
		else
			info.prompt.Enabled = true
			if info.helpPrompt then
				info.helpPrompt.Enabled = false
			end
		end
	end

	-- 2. Refresh prompt slot install:
	-- - Harus ada pemain yang bawa part dengan Kind yang cocok
	-- - Untuk Panel: Engine harus sudah terpasang
	-- - Jika slot sudah filled: prompt mati
	-- - Untuk Panel ganda: hanya SATU slot panel kosong yang prompt-nya aktif (sequential)
	local engineIn = isEngineInstalled()

	-- cari kind apa saja yang sedang dibawa
	local carriedKinds: { [string]: boolean } = {}
	for _, k in pairs(carriedKind) do
		carriedKinds[k] = true
	end

	local firstEmptyPanelHandled = false
	for _, rec in pairs(slots) do
		if rec.filled then
			rec.prompt.Enabled = false
		elseif rec.kind == "Engine" then
			-- Engine prompt: nyala kalau ada yang bawa Engine
			rec.prompt.Enabled = (carriedKinds["Engine"] == true)
		elseif rec.kind == "Panel" then
			-- Panel prompt: nyala kalau bawa Panel & slot depan yang kosong.
			-- (Engine-first di-cek di tryInsert -> kasih WARNING, bukan disembunyikan.)
			if carriedKinds["Panel"] == true and not firstEmptyPanelHandled then
				rec.prompt.Enabled = true
				firstEmptyPanelHandled = true
			else
				rec.prompt.Enabled = false
			end
		else
			rec.prompt.Enabled = false
		end
	end

	if onCarryChanged then
		onCarryChanged()
	end
	isRefreshing = false
end

-- ----------------------------------------------------------------------
-- Pickup & Drop
-- ----------------------------------------------------------------------

function AssemblyService.getCarried(player: Player): BasePart?
	return carriedPart[player]
end

function AssemblyService.canPickup(player: Player, part: BasePart): boolean
	if carriedPart[player] ~= nil then return false end
	if pickups[part] == nil then return false end
	for _, p in pairs(carriedPart) do
		if p == part then return false end
	end

	-- Tidak boleh ambil part assembly jika sedang membawa baterai
	local char = player.Character
	if char and char:GetAttribute(Config.CarryingAttribute) == true then
		return false
	end

	return true
end

-- Hentikan loop penggerak engine & bersihkan resource runtime-nya.
local function stopEngineRuntime(part: BasePart)
	local rt = engineLockRuntimes[part]
	if not rt then return end
	if rt.conn then
		rt.conn:Disconnect()
	end
	engineLockRuntimes[part] = nil
end

local function clearEngineCarrierWelds(player: Player)
	-- Sisa weld dari versi lama (kalau ada) dibersihkan supaya pemain tidak nyangkut.
	local char = player.Character
	if not char then return end
	for _, inst in ipairs(char:GetDescendants()) do
		if inst:IsA("Weld") and string.find(inst.Name, "EngineCarryWeld", 1, true) then
			inst:Destroy()
		end
	end
end

local function detachPlayer(player: Player)
	local part = carriedPart[player]
	clearEngineCarrierWelds(player)
	carriedPart[player] = nil
	carriedKind[player] = nil
	carrierSide[player] = nil

	if part then
		local rt = engineLockRuntimes[part]
		if rt then
			rt.offsets[player] = nil
			-- Driver utama lepas -> alihkan driver ke carrier yang tersisa.
			if rt.driver == player then
				local ec = engineCarriers[part]
				rt.driver = ec and (ec.left or ec.right) or nil
			end
			if next(rt.offsets) == nil then
				stopEngineRuntime(part)
			end
		end
	end

	-- Kembalikan properti fisik karakter ke kondisi semula.
	local hum = getHumanoid(player)
	if hum and savedSpeed[player] then
		hum.WalkSpeed = savedSpeed[player].walk
		hum.JumpPower = savedSpeed[player].jump
		hum.AutoRotate = savedSpeed[player].autoRotate
	end
	savedSpeed[player] = nil

	local char = player.Character
	if char then
		char:SetAttribute("CarryingAssemblyPart", nil)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Massless = false
		end
	end

	CarryAnimator.stop(player)
end

-- Posisi carrier RELATIF terhadap Attachment sisi (world), diukur dari rig Aer.
-- Dipakai untuk menempatkan pemain di sisi engine SAAT mulai membawa (snap sekali).
local function getCarrierSnapOffset(side: "Left" | "Right"): CFrame
	if side == "Left" then
		return CFrame.new(-1.2783, -0.0648, 0.0032) * CFrame.Angles(0, math.rad(-90), 0)
	end
	return CFrame.new(0.9781, -0.0648, 0.0032) * CFrame.Angles(0, math.rad(90), 0)
end

-- TANPA WELD. Engine tetap Anchored & rotasinya DIKUNCI (tidak ikut muter arah player).
-- Engine hanya BERGESER mengikuti perpindahan carrier utama; pemain jalan bebas
-- sehingga animasi jalan tetap main.
local function attachEngineCarrier(part: BasePart, player: Player, side: "Left" | "Right")
	local info = pickups[part]
	if not info then return false end
	local att = (side == "Left") and info.attachments.left or info.attachments.right
	if not att then return false end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	part.Anchored = true -- Engine tidak jatuh; digerakkan lewat CFrame.

	-- Snap pemain ke sisi engine sekali di awal (biar berdiri di posisi pegangan).
	root.CFrame = att.WorldCFrame * getCarrierSnapOffset(side)

	local rt = engineLockRuntimes[part]
	if not rt then
		rt = {
			offsets = {},
			driver = player,
			lockedRotation = part.CFrame.Rotation,
		}
		engineLockRuntimes[part] = rt
	end
	-- Simpan delta WORLD engine terhadap carrier ini saat mulai bawa.
	rt.offsets[player] = CFrame.new(part.Position - root.Position)

	if not rt.driver then
		rt.driver = player
	end

	-- Terbitkan JUMLAH carrier ke part, supaya CLIENT bisa memutuskan
	-- menampilkan prompt "Help Carry" secara lokal (Enabled global di server
	-- bikin carrier sendiri ikut melihat prompt itu).
	local ecNow = engineCarriers[part]
	local count = 0
	if ecNow then
		if ecNow.left then count += 1 end
		if ecNow.right then count += 1 end
	end
	part:SetAttribute("EngineCarrierCount", count)

	-- Loop: engine mengikuti PERGESERAN driver (translasi), rotasi tetap terkunci.
	if not rt.conn then
		local RunService = game:GetService("RunService")
		local lastDriverPos: Vector3? = nil
		rt.conn = RunService.Heartbeat:Connect(function()
			local ec = engineCarriers[part]
			if not ec or not part.Parent then
				if rt.conn then rt.conn:Disconnect(); rt.conn = nil end
				return
			end

			-- Pilih driver aktif (carrier utama; fallback ke yang tersisa).
			local driver = rt.driver
			if driver ~= ec.left and driver ~= ec.right then
				driver = ec.left or ec.right
				rt.driver = driver
				lastDriverPos = nil
			end

			local dChar = driver and driver.Character
			local dRoot = dChar and dChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if dRoot and rt.lockedRotation then
				if lastDriverPos then
					local delta = dRoot.Position - lastDriverPos
					-- Hanya translasi horizontal; abaikan komponen naik-turun bob animasi.
					part.CFrame = CFrame.new(part.Position + Vector3.new(delta.X, 0, delta.Z)) * rt.lockedRotation
				end
				lastDriverPos = dRoot.Position
			end
		end)
	end

	return true
end

function AssemblyService.pickup(player: Player, part: BasePart): boolean
	if not AssemblyService.canPickup(player, part) then
		return false
	end

	local info = pickups[part]
	if not info then return false end

	local hum = getHumanoid(player)
	if not hum then return false end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	carriedPart[player] = part
	carriedKind[player] = info.kind

	if not savedSpeed[player] then
		savedSpeed[player] = { walk = hum.WalkSpeed, jump = hum.JumpPower, autoRotate = hum.AutoRotate }
	end

	if player.Character then
		player.Character:SetAttribute("CarryingAssemblyPart", info.kind)
	end

	info.prompt.Enabled = false

	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	if info.kind == "Panel" then
		hum.WalkSpeed = Config.CarryWalkSpeed
		hum.JumpPower = Config.CarryJumpPower

		local weld = Instance.new("Weld")
		weld.Name = "AssemblyCarryWeld"
		weld.Part0 = root
		weld.Part1 = part
		weld.C0 = Config.PanelCarryOffset
		weld.Parent = part

		part.CFrame = root.CFrame * weld.C0
		CarryAnimator.play(player, Config.PanelCarryAnimId)
	else
		-- Engine: carrier 1 mulai dari Attachment Left.
		carrierSide[player] = "Left"
		engineCarriers[part] = { left = player, right = nil }

		hum.WalkSpeed = Config.EngineSoloSpeed
		hum.JumpPower = Config.CarryJumpPower

		if not attachEngineCarrier(part, player, "Left") then
			engineCarriers[part] = nil
			detachPlayer(player)
			part.Anchored = true
			part.CanCollide = true
			part.CanTouch = true
			part.CanQuery = true
			return false
		end

		CarryAnimator.play(player, Config.EngineLeftAnimId)

		-- Nyalakan prompt Help Carry untuk pemain kedua
		if info.helpPrompt then
			info.helpPrompt.Enabled = true
		end
	end

	AssemblyService.refreshPrompts()
	return true
end

function AssemblyService.canHelpCarry(player: Player, part: BasePart): boolean
	if carriedPart[player] ~= nil then return false end
	if pickups[part] == nil then return false end
	local ec = engineCarriers[part]
	if not ec then return false end

	-- Harus ada tepat 1 carrier yang sedang bawa, dan 1 slot kosong
	local hasOne = (ec.left ~= nil and ec.right == nil) or (ec.left == nil and ec.right ~= nil)
	if not hasOne then return false end
	if ec.left == player or ec.right == player then return false end

	local char = player.Character
	if not char then return false end
	if char:GetAttribute(Config.CarryingAttribute) == true then return false end
	return true
end

function AssemblyService.helpCarry(player: Player, part: BasePart): boolean
	if not AssemblyService.canHelpCarry(player, part) then
		return false
	end
	local ec = engineCarriers[part]
	if not ec then return false end

	local hum = getHumanoid(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) then return false end

	-- Pilih sisi yang kosong
	local side: "Left" | "Right"
	if ec.left == nil then
		side = "Left"
		ec.left = player
	else
		side = "Right"
		ec.right = player
	end

	carriedPart[player] = part
	carriedKind[player] = "Engine"
	carrierSide[player] = side

	if not savedSpeed[player] then
		savedSpeed[player] = { walk = hum.WalkSpeed, jump = hum.JumpPower, autoRotate = hum.AutoRotate }
	end

	char:SetAttribute("CarryingAssemblyPart", "Engine")

	if not attachEngineCarrier(part, player, side) then
		if side == "Left" then ec.left = nil else ec.right = nil end
		detachPlayer(player)
		return false
	end

	local animId = (side == "Left") and Config.EngineLeftAnimId or Config.EngineRightAnimId
	CarryAnimator.play(player, animId)

	-- Update walkspeed KEDUA pemain ke EngineCoopSpeed (14)
	if ec.left and ec.left.Character then
		local hL = ec.left.Character:FindFirstChildOfClass("Humanoid")
		if hL then hL.WalkSpeed = Config.EngineCoopSpeed end
	end
	if ec.right and ec.right.Character then
		local hR = ec.right.Character:FindFirstChildOfClass("Humanoid")
		if hR then hR.WalkSpeed = Config.EngineCoopSpeed end
	end

	-- Matikan prompt Help Carry karena slot sudah penuh (2 orang)
	local info = pickups[part]
	if info and info.helpPrompt then
		info.helpPrompt.Enabled = false
	end

	AssemblyService.refreshPrompts()
	return true
end

function AssemblyService.drop(player: Player)
	local part = carriedPart[player]
	if not part then return end

	local info = pickups[part]
	local kind = carriedKind[player]

	if kind == "Engine" and engineCarriers[part] then
		local ec = engineCarriers[part]
		local otherPlayer = (ec.left == player) and ec.right or ((ec.right == player) and ec.left or nil)

		part:SetAttribute("EngineCarrierCount", 0) -- akan di-set ulang di bawah sesuai kondisi

		if otherPlayer and (otherPlayer.Parent ~= nil or otherPlayer.Character ~= nil) then
			-- ADA PEMAIN LAIN: TETAP BAWA SENDIRI JANGAN JATOH (Keputusan Aer #1)
			-- 1. Lepas pemain yang drop
			detachPlayer(player)

			-- 2. Kosongkan slot pemain yang drop
			if ec.left == player then ec.left = nil end
			if ec.right == player then ec.right = nil end

			-- 3. Hapus weld engine carrier (weld berada pada RootPart carrier)
			clearEngineCarrierWelds(player)

			-- 4. Pemain tersisa tetap di Attachment-nya; Engine tetap tidak bergerak
			local otherSide = carrierSide[otherPlayer] or "Left"
			attachEngineCarrier(part, otherPlayer, otherSide)

			-- 5. Turunkan kecepatan otherPlayer ke EngineSoloSpeed (8)
			local otherHum = getHumanoid(otherPlayer)
			if otherHum then
				otherHum.WalkSpeed = Config.EngineSoloSpeed
			end

			-- 6. Nyalakan lagi Help Carry prompt agar pemain lain bisa bantu
			if info and info.helpPrompt then
				info.helpPrompt.Enabled = true
			end
			part:SetAttribute("EngineCarrierCount", 1) -- tinggal 1 carrier -> Help Carry boleh muncul

			AssemblyService.refreshPrompts()
			return
		else
			-- TIDAK ADA PEMAIN LAIN: Engine jatuh ke tanah di depan pemain
			engineCarriers[part] = nil
			stopEngineRuntime(part)
			part:SetAttribute("EngineCarrierCount", 0)
			detachPlayer(player)

			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
					child:Destroy()
				end
			end

			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				part.CFrame = root.CFrame * CFrame.new(0, -1.2, -3)
			elseif info then
				part.CFrame = info.homeCF
			end

			part.Anchored = true
			part.CanCollide = true
			part.CanTouch = true
			part.CanQuery = true

			if info and info.helpPrompt then
				info.helpPrompt.Enabled = false
			end

			AssemblyService.refreshPrompts()
			return
		end
	end

	-- Panel drop (normal solo)
	detachPlayer(player)

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		part.CFrame = root.CFrame * CFrame.new(0, -1.5, -3)
	elseif info then
		part.CFrame = info.homeCF
	end

	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = true
	part.CanQuery = true

	AssemblyService.refreshPrompts()
end

-- ----------------------------------------------------------------------
-- Insert / Pasang ke Slot
-- ----------------------------------------------------------------------

local function tryInsert(player: Player, slotPart: BasePart): boolean
	local rec = slots[slotPart]
	if not rec or rec.filled then return false end

	local carried = carriedPart[player]
	local kind = carriedKind[player]
	if not carried or kind ~= rec.kind then return false end

	-- Engine gating: Panel tidak bisa dipasang sebelum Engine -> WARNING, bukan diam.
	if rec.kind == "Panel" and not isEngineInstalled() then
		warn_(player, "Pasang Engine dulu sebelum Panel!")
		return false
	end

	-- Jarak pemain ke slot
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		if (root.Position - slotPart.Position).Magnitude > (Config.InsertPromptDistance + 6) then
			return false
		end
	end

	-- KUNCI SLOT
	rec.filled = true

	-- Tampilkan placeholder slot
	slotPart.Transparency = 0
	slotPart.CanCollide = true
	slotPart.CanQuery = false
	slotPart.CanTouch = false
	rec.prompt.Enabled = false

	-- Bersihkan part bawaan untuk SEMUA carrier yang membawa part ini (Engine bisa 2 orang)
	local ec = engineCarriers[carried]
	if ec then
		if ec.left then detachPlayer(ec.left) end
		if ec.right then detachPlayer(ec.right) end
		engineCarriers[carried] = nil
	else
		detachPlayer(player)
	end
	-- Hentikan loop penggerak engine & reset atribut supaya prompt/anim tidak nyangkut.
	stopEngineRuntime(carried)
	carried:SetAttribute("EngineCarrierCount", 0)
	local carriedInfo = pickups[carried]
	if carriedInfo and carriedInfo.helpPrompt then
		carriedInfo.helpPrompt.Enabled = false
	end
	pickups[carried] = nil

	carried:Destroy()

	-- Update progress
	local filled, total = countFilled()
	if generatorModel then
		generatorModel:SetAttribute("AssemblyProgress", string.format("%d/%d", filled, total))
		if filled >= total then
			generatorModel:SetAttribute("GeneratorAssembled", true)
			if onAssembledCallback then
				onAssembledCallback(generatorModel)
			end
		end
	end

	AssemblyService.refreshPrompts()
	return true
end

-- ----------------------------------------------------------------------
-- Registrasi Slot & Pickup
-- ----------------------------------------------------------------------

local function registerSlot(part: BasePart)
	if slots[part] then return end

	local kindAttr = part:GetAttribute("Kind")
	local kind = typeof(kindAttr) == "string" and kindAttr or "Engine"

	-- deteksi generator model
	if not generatorModel then
		local anc = part:FindFirstAncestorOfClass("Model")
		if anc and anc.Name == "Generator" then
			generatorModel = anc
		end
	end

	-- Sembunyikan placeholder di runtime (bukan dihapus)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true

	local prompt = part:FindFirstChild("AssemblyInsertPrompt") :: ProximityPrompt?
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AssemblyInsertPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = "Install"
	prompt.ObjectText = kind
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = Config.InsertPromptDistance
	prompt.HoldDuration = Config.InsertDuration
	prompt.RequiresLineOfSight = Config.RequireLineOfSight
	prompt.Enabled = false

	prompt.Triggered:Connect(function(player)
		tryInsert(player, part)
	end)

	slots[part] = {
		part = part,
		kind = kind,
		filled = false,
		prompt = prompt,
	}
end

local function registerPickup(part: BasePart)
	if pickups[part] then return end

	local kindAttr = part:GetAttribute("Kind")
	local kind = typeof(kindAttr) == "string" and kindAttr or "Engine"

	part.Anchored = true

	local prompt = part:FindFirstChild("AssemblyPickupPrompt", true) :: ProximityPrompt?
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AssemblyPickupPrompt"
		prompt.Parent = part
	end
	-- Engine memiliki Attachment "Left" dan "Right" buatan Aer.
	-- Pickup pertama tampil di sisi Left; pemain kedua menerima Help Carry di Right.
	local leftAttachment: Attachment? = nil
	local rightAttachment: Attachment? = nil
	if kind == "Engine" then
		local candidateLeft = part:FindFirstChild("Left")
		local candidateRight = part:FindFirstChild("Right")
		if candidateLeft and candidateLeft:IsA("Attachment") then
			leftAttachment = candidateLeft
		end
		if candidateRight and candidateRight:IsA("Attachment") then
			rightAttachment = candidateRight
		end
	end

	-- Fallback parent tetap ke part bila Attachment belum ada, supaya engine tidak deadlock.
	prompt.Parent = leftAttachment or part
	prompt.ActionText = Config.PickupPromptText
	prompt.ObjectText = kind
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = Config.PickupPromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = Config.RequireLineOfSight
	prompt.Enabled = true

	prompt.Triggered:Connect(function(player)
		AssemblyService.pickup(player, part)
	end)

	local helpPrompt: ProximityPrompt? = nil
	if kind == "Engine" then
		helpPrompt = part:FindFirstChild("EngineHelpCarryPrompt", true) :: ProximityPrompt?
		if not helpPrompt then
			helpPrompt = Instance.new("ProximityPrompt")
			helpPrompt.Name = "EngineHelpCarryPrompt"
			helpPrompt.Parent = part
		end
		helpPrompt.ActionText = "Help Carry"
		helpPrompt.ObjectText = "Engine"
		-- Prompt bantuan ditempatkan di Attachment Right (bukan di tengah Engine).
		helpPrompt.Parent = rightAttachment or part
		helpPrompt.KeyboardKeyCode = Enum.KeyCode.E
		helpPrompt.MaxActivationDistance = Config.PickupPromptDistance + 4
		helpPrompt.HoldDuration = 0.5
		helpPrompt.RequiresLineOfSight = false
		helpPrompt.Enabled = false

		helpPrompt.Triggered:Connect(function(player)
			AssemblyService.helpCarry(player, part)
		end)
	end

	pickups[part] = {
		kind = kind,
		prompt = prompt,
		helpPrompt = helpPrompt,
		attachments = {left = leftAttachment, right = rightAttachment},
		homeCF = part.CFrame,
	}
end

-- ----------------------------------------------------------------------
-- Query Status
-- ----------------------------------------------------------------------

function AssemblyService.isAssembled(): boolean
	local filled, total = countFilled()
	return total > 0 and filled >= total
end

function AssemblyService.getProgress(): (number, number)
	return countFilled()
end

-- ----------------------------------------------------------------------
-- START
-- ----------------------------------------------------------------------

function AssemblyService.start(opts: {
	onAssembled: ((genModel: Model) -> ())?,
}?)
	if opts and opts.onAssembled then
		onAssembledCallback = opts.onAssembled
	end

	-- Bind existing tagged slots
	for _, p in ipairs(CollectionService:GetTagged("AssemblySlot")) do
		if p:IsA("BasePart") then
			registerSlot(p)
		end
	end
	CollectionService:GetInstanceAddedSignal("AssemblySlot"):Connect(function(p)
		if p:IsA("BasePart") then registerSlot(p) end
	end)

	-- Bind existing tagged pickups
	for _, p in ipairs(CollectionService:GetTagged("AssemblyPickup")) do
		if p:IsA("BasePart") then
			registerPickup(p)
		end
	end
	CollectionService:GetInstanceAddedSignal("AssemblyPickup"):Connect(function(p)
		if p:IsA("BasePart") then registerPickup(p) end
	end)

	-- Inisialisasi progress attribute
	local filled, total = countFilled()
	if generatorModel then
		generatorModel:SetAttribute("AssemblyProgress", string.format("%d/%d", filled, total))
		generatorModel:SetAttribute("GeneratorAssembled", false)
	end

	-- Lifecycle player drop on death
	local function bindChar(player: Player)
		player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Connect(function()
					AssemblyService.drop(player)
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(bindChar)
	for _, p in ipairs(Players:GetPlayers()) do
		bindChar(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		AssemblyService.drop(p)
		savedSpeed[p] = nil
	end)

	AssemblyService.refreshPrompts()
end

return AssemblyService
