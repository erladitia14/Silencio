--!strict
--[[
	CaseService — v2 rebuild (pragmatic)

	Slot = BasePart placeholder yang SUDAH diposisikan Aer di dalam case
	(tag "BatterySlot"). Baterai placeholder ini juga jadi visual "baterai
	terpasang" begitu diisi.

	Alur insert:
	1. Prompt "Insert" hanya muncul di slot kosong BERIKUTNYA (kiri->kanan).
	2. Saat pemain punya baterai & tekan prompt (tahan 2 detik):
	   - placeholder slot DITAMPILKAN (Transparency 0) = keliatan terisi.
	   - baterai di tangan pemain DIHANCURKAN via BatteryService.consume().
	   - prompt slot ini MATI, slot berikutnya NYALA.
	3. Progress diterbitkan; kalau semua slot terisi -> puzzle Complete.

	Placeholder default disembunyikan saat game jalan (belum terisi).
]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local CaseService = {}

local cases: { [Instance]: any } = {}

-- callback dipasang orchestrator
local onSlotFilled: ((player: Player, case: Instance, slot: BasePart) -> ())? = nil
local getCarried: ((player: Player) -> BasePart?)? = nil
local consumeCarried: ((player: Player) -> BasePart?)? = nil

-- ============================================================
-- UTIL
-- ============================================================

local function findCaseOf(slot: BasePart): Instance?
	local parent: Instance? = slot.Parent
	while parent do
		if CollectionService:HasTag(parent, Config.CaseTag) then
			return parent
		end
		parent = parent.Parent
	end
	return nil
end

-- ============================================================
-- PROMPT SLOT
-- ============================================================

local function ensureSlotPrompt(slot: BasePart): ProximityPrompt
	local p = slot:FindFirstChild("BatteryInsertPrompt") :: ProximityPrompt?
	if not p then
		p = Instance.new("ProximityPrompt")
		p.Name = "BatteryInsertPrompt"
		p.Parent = slot
	end
	p.ActionText = Config.InsertPromptText
	p.ObjectText = "Slot"
	p.KeyboardKeyCode = Config.InsertPromptKey
	p.MaxActivationDistance = Config.InsertPromptDistance
	p.RequiresLineOfSight = Config.RequireLineOfSight
	p.HoldDuration = Config.InsertDuration
	return p
end

-- Hanya slot KOSONG paling depan (kiri->kanan) yang prompt-nya nyala.
local function updateSlotPrompts(rec: any)
	local nextIndex = 0
	for i, slot in ipairs(rec.slots) do
		if not rec.filled[slot] then
			nextIndex = i
			break
		end
	end
	for i, slot in ipairs(rec.slots) do
		local prompt = slot:FindFirstChild("BatteryInsertPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = (i == nextIndex)
		end
	end
end

-- ============================================================
-- PASANG
-- ============================================================

local function tryInsert(player: Player, case: Instance, slot: BasePart): boolean
	local rec = cases[case]
	if not rec then return false end
	if rec.filled[slot] then return false end          -- slot sudah terisi

	-- pemain harus membawa baterai
	local battery = getCarried and getCarried(player) or nil
	if not battery then return false end

	-- validasi jarak (anti-exploit ringan)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		if (root.Position - slot.Position).Magnitude > (Config.InsertPromptDistance + 6) then
			return false
		end
	end

	-- KUNCI SLOT
	rec.filled[slot] = player

	-- Placeholder slot ditampilkan = baterai terlihat terpasang
	slot.Transparency = 0
	slot.CanCollide = false
	slot.CanQuery = false
	slot.CanTouch = false

	-- Matikan prompt slot ini
	local prompt = slot:FindFirstChild("BatteryInsertPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end

	-- Hancurkan baterai di tangan pemain
	if consumeCarried then
		consumeCarried(player)
	end

	-- Buka slot berikutnya
	updateSlotPrompts(rec)

	-- Progress
	local filled = 0
	for _ in pairs(rec.filled) do filled += 1 end
	if case:IsA("Model") or case:IsA("BasePart") then
		case:SetAttribute(Config.ProgressAttribute, string.format("%d/%d", filled, rec.total))
		if filled >= rec.total then
			case:SetAttribute(Config.CompletedAttribute, true)
		end
	end

	if onSlotFilled then
		onSlotFilled(player, case, slot)
	end
	Config.log("slot filled", slot.Name, "by", player.Name, filled .. "/" .. rec.total)
	return true
end

-- ============================================================
-- PROGRESS
-- ============================================================

function CaseService.getProgress(case: Instance): (number, number)
	local rec = cases[case]
	if not rec then return 0, 0 end
	local n = 0
	for _ in pairs(rec.filled) do n += 1 end
	return n, rec.total
end

function CaseService.isComplete(case: Instance): boolean
	local n, total = CaseService.getProgress(case)
	return total > 0 and n >= total
end

-- ============================================================
-- REGISTER
-- ============================================================

local function registerCase(case: Instance)
	if cases[case] then return end

	-- kumpulkan slot bertag di bawah case ini
	local slots: { BasePart } = {}
	for _, s in ipairs(CollectionService:GetTagged(Config.SlotTag)) do
		if s:IsA("BasePart") and findCaseOf(s) == case then
			table.insert(slots, s)
		end
	end

	-- urutkan kiri->kanan (sumbu X relatif ke case)
	local caseCF: CFrame = case:IsA("Model") and case:GetPivot() or (case :: any).CFrame
	table.sort(slots, function(a, b)
		return caseCF:PointToObjectSpace(a.Position).X < caseCF:PointToObjectSpace(b.Position).X
	end)

	local rec = {
		total = #slots,
		filled = {} :: { [BasePart]: Player },
		slots = slots,
	}

	for _, slot in ipairs(slots) do
		local p = ensureSlotPrompt(slot)
		p.Triggered:Connect(function(player)
			tryInsert(player, case, slot)
		end)
	end

	cases[case] = rec
	updateSlotPrompts(rec)

	if case:IsA("Model") or case:IsA("BasePart") then
		case:SetAttribute(Config.ProgressAttribute, string.format("0/%d", rec.total))
	end

	Config.log("registered case", case:GetFullName(), "with", rec.total, "slots")
end

-- ============================================================
-- SAAT GAME BERJALAN: sembunyikan placeholder kosong
-- ============================================================

function CaseService.hidePlaceholders()
	for _, rec in pairs(cases) do
		for _, slot in ipairs(rec.slots) do
			if not rec.filled[slot] then
				slot.Transparency = 1
				slot.CanCollide = false
				slot.CanQuery = false
			end
		end
	end
end

-- ============================================================
-- INIT
-- ============================================================

function CaseService.start(opts: {
	onSlotFilled: ((player: Player, case: Instance, slot: BasePart) -> ())?,
	getCarried: ((player: Player) -> BasePart?)?,
	consumeCarried: ((player: Player) -> BasePart?)?,
})
	onSlotFilled = opts.onSlotFilled
	getCarried = opts.getCarried
	consumeCarried = opts.consumeCarried

	for _, case in ipairs(CollectionService:GetTagged(Config.CaseTag)) do
		registerCase(case)
	end
	CollectionService:GetInstanceAddedSignal(Config.CaseTag):Connect(registerCase)

	Config.log("CaseService started,", #CollectionService:GetTagged(Config.CaseTag), "cases")
end

return CaseService