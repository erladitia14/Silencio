--!strict
--[[
	CaseService — mengelola wadah baterai (tag "BatteryCase") dan slot-nya
	(tag "BatterySlot").

	PENTING soal placeholder:
	Slot = BasePart placeholder yang SUDAH diposisikan Aer di dalam case.
	Posisi & arah tiap slot dibaca RELATIF ke case, jadi kalau case digeser
	atau diputar, titik pasangnya tetap ikut.

	Di Studio (edit mode) placeholder tetap kelihatan supaya bisa ditata.
	Saat game BERJALAN baru disembunyikan + collision dimatikan.
	Placeholder TIDAK PERNAH dihapus.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local CaseService = {}

local cases: { [Instance]: any } = {}
local slotOwners: { [BasePart]: Instance } = {}       -- slot -> case

-- dipasang orchestrator
local onSlotFilled: ((player: Player, case: Instance, slot: BasePart, battery: BasePart) -> ())? = nil
local isBatteryInserted: ((battery: BasePart) -> boolean)? = nil
local markInserted: ((player: Player, battery: BasePart, cf: CFrame) -> ())? = nil
local getCarried: ((player: Player) -> BasePart?)? = nil

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

-- Posisi slot relatif ke case (tahan geser/putar case)
local function localSlotCFrame(case: Instance, slot: BasePart): CFrame
	local caseCF: CFrame
	if case:IsA("Model") then
		caseCF = case:GetPivot()
	elseif case:IsA("BasePart") then
		caseCF = case.CFrame
	else
		caseCF = CFrame.new()
	end
	return caseCF:ToObjectSpace(slot.CFrame)
end

local function worldSlotCFrame(case: Instance, localCF: CFrame): CFrame
	local caseCF: CFrame
	if case:IsA("Model") then
		caseCF = case:GetPivot()
	elseif case:IsA("BasePart") then
		caseCF = case.CFrame
	else
		caseCF = CFrame.new()
	end
	return caseCF * localCF
end

-- ============================================================
-- PROMPT SLOT
-- ============================================================

local function ensureSlotPrompt(slot: BasePart)
	local existing = slot:FindFirstChild("BatteryInsertPrompt")
	if existing then
		return existing :: ProximityPrompt
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "BatteryInsertPrompt"
	p.ActionText = Config.InsertPromptText
	p.ObjectText = "Slot"
	p.KeyboardKeyCode = Config.InsertPromptKey
	p.MaxActivationDistance = Config.InsertPromptDistance
	p.RequiresLineOfSight = Config.RequireLineOfSight
	-- HoldDuration dipakai untuk "waktu pasang" (2 detik diam)
	p.HoldDuration = Config.InsertDuration
	p.Parent = slot
	return p
end

-- ============================================================
-- PASANG
-- ============================================================

local function tryInsert(player: Player, case: Instance, slot: BasePart): boolean
	local rec = cases[case]
	if not rec then
		return false
	end
	if rec.filled[slot] then
		return false                        -- slot sudah terisi
	end

	-- pemain harus benar-benar membawa baterai
	local battery = getCarried and getCarried(player) or nil
	if not battery then
		return false
	end
	if isBatteryInserted and isBatteryInserted(battery) then
		return false
	end

	-- validasi jarak (anti-exploit ringan): pemain masih dekat slot?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local dist = (root.Position - slot.Position).Magnitude
		if dist > (Config.InsertPromptDistance + 6) then
			return false
		end
	end

	-- KUNCI SLOT DULU (cegah dua pemain mengisi slot sama)
	rec.filled[slot] = player

	local cf = worldSlotCFrame(case, rec.slotLocal[slot] or CFrame.new())
	if markInserted then
		markInserted(player, battery, cf)
	end
	-- simpan referensi baterai yang terpasang
	rec.inserted[slot] = battery

	-- sembunyikan placeholder (bukan dihapus)
	slot.Transparency = 1
	slot.CanCollide = false
	slot.CanQuery = false
	local prompt = slot:FindFirstChild("BatteryInsertPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end

	if onSlotFilled then
		onSlotFilled(player, case, slot, battery)
	end
	Config.log("slot filled", slot.Name, "by", player.Name)
	return true
end

-- ============================================================
-- PROGRESS
-- ============================================================

local function countFilled(case: Instance): (number, number)
	local rec = cases[case]
	if not rec then
		return 0, 0
	end
	local n = 0
	for _, _ in pairs(rec.filled) do
		n += 1
	end
	return n, rec.total
end

function CaseService.getProgress(case: Instance): (number, number)
	return countFilled(case)
end

function CaseService.isComplete(case: Instance): boolean
	local n, total = countFilled(case)
	return total > 0 and n >= total
end

-- ============================================================
-- REGISTER
-- ============================================================

local function registerCase(case: Instance)
	if cases[case] then
		return
	end

	-- kumpulkan slot: descendant ber-tag BatterySlot yang berada di bawah case ini
	local slots: { BasePart } = {}
	for _, s in ipairs(CollectionService:GetTagged(Config.SlotTag)) do
		if s:IsA("BasePart") and findCaseOf(s) == case then
			table.insert(slots, s)
		end
	end

	-- Urutkan slot secara SPASIAL (kiri->kanan) supaya nomor slot stabil
	-- dan tidak bergantung urutan GetChildren.
	local caseCF: CFrame = case:IsA("Model") and case:GetPivot() or (case :: any).CFrame
	table.sort(slots, function(a, b)
		local la = caseCF:PointToObjectSpace(a.Position)
		local lb = caseCF:PointToObjectSpace(b.Position)
		return la.X < lb.X
	end)

	local rec = {
		total = #slots,
		filled = {} :: { [BasePart]: Player },
		inserted = {} :: { [BasePart]: BasePart },
		slotLocal = {} :: { [BasePart]: CFrame },
		slots = slots,
	}

	for _, slot in ipairs(slots) do
		rec.slotLocal[slot] = localSlotCFrame(case, slot)
		slotOwners[slot] = case
		local p = ensureSlotPrompt(slot)
		p.Triggered:Connect(function(player)
			tryInsert(player, case, slot)
		end)
	end

	cases[case] = rec

	-- Terbitkan progress awal
	if case:IsA("Model") or case:IsA("BasePart") then
		case:SetAttribute(Config.ProgressAttribute, string.format("0/%d", rec.total))
	end

	Config.log("registered case", case:GetFullName(), "with", rec.total, "slots")
end

local function unregisterCase(case: Instance)
	cases[case] = nil
end

-- ============================================================
-- SAAT GAME BERJALAN: sembunyikan placeholder
-- ============================================================

function CaseService.hidePlaceholders()
	for case, rec in pairs(cases) do
		for _, slot in ipairs(rec.slots) do
			-- Kalau slot sudah terisi, biarkan (baterai asli terlihat).
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
	onSlotFilled: ((player: Player, case: Instance, slot: BasePart, battery: BasePart) -> ())?,
	isBatteryInserted: ((battery: BasePart) -> boolean)?,
	markInserted: ((player: Player, battery: BasePart, cf: CFrame) -> ())?,
	getCarried: ((player: Player) -> BasePart?)?,
})
	onSlotFilled = opts.onSlotFilled
	isBatteryInserted = opts.isBatteryInserted
	markInserted = opts.markInserted
	getCarried = opts.getCarried

	for _, case in ipairs(CollectionService:GetTagged(Config.CaseTag)) do
		registerCase(case)
	end
	CollectionService:GetInstanceAddedSignal(Config.CaseTag):Connect(function(case)
		registerCase(case)
	end)
	CollectionService:GetInstanceRemovedSignal(Config.CaseTag):Connect(function(case)
		unregisterCase(case)
	end)

	-- Slot yang ditambah runtime
	CollectionService:GetInstanceAddedSignal(Config.SlotTag):Connect(function(slot)
		if slot:IsA("BasePart") then
			local case = findCaseOf(slot)
			if case and cases[case] then
				-- case sudah terdaftar -> daftarkan slot tambahan
				local rec = cases[case]
				if not rec.slotLocal[slot] then
					rec.slotLocal[slot] = localSlotCFrame(case, slot)
					rec.total += 1
					slotOwners[slot] = case
					local p = ensureSlotPrompt(slot)
					p.Triggered:Connect(function(player)
						tryInsert(player, case, slot)
					end)
				end
			elseif case then
				registerCase(case)
			end
		end
	end)

	Config.log("CaseService started,", #CollectionService:GetTagged(Config.CaseTag), "cases")
end

return CaseService
