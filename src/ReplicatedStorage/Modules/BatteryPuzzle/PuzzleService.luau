--!strict
--[[
	PuzzleService — progress tim & status penyelesaian.

	Modul ini SENGAJA tidak tahu apa-apa soal lampu/pintu.
	Saat puzzle selesai, ia hanya:
	  1. Set Attribute di Model case  -> sistem lain boleh MEMBACA
	  2. Fire BindableEvent "Completed" -> sistem lain boleh MENYAMBUNG

	Jadi hubungan ke lampu nanti dibuat lewat modul penghubung terpisah,
	tanpa mengubah file ini dan tanpa menyentuh KeySystem/SafeZone.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local PuzzleService = {}

local cases: { [Instance]: any } = {}
local events: { [Instance]: BindableEvent } = {}

-- ============================================================
-- EVENT (kanal untuk sistem lain)
-- ============================================================

function PuzzleService.getEvent(case: Instance): BindableEvent?
	return events[case]
end

local function ensureEvent(case: Instance): BindableEvent
	local existing = case:FindFirstChild("BatteryPuzzleCompleted")
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = "BatteryPuzzleCompleted"
	ev.Parent = case
	return ev
end

-- ============================================================
-- BROADCAST progress ke semua client
-- ============================================================

local function broadcast(case: Instance, filled: number, total: number, complete: boolean)
	if not Config.BroadcastProgress then
		return
	end
	local ev = game:GetService("ReplicatedStorage"):FindFirstChild("BatteryPuzzleEvent")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireAllClients(case, filled, total, complete)
	end
end

-- ============================================================
-- LAPOR SLOT TERISI
-- ============================================================

function PuzzleService.reportSlotFilled(case: Instance, slot: BasePart, filled: number, total: number)
	local rec = cases[case]
	if not rec then
		return
	end
	local complete = total > 0 and filled >= total

	if case:IsA("Model") or case:IsA("BasePart") then
		case:SetAttribute(Config.ProgressAttribute, string.format("%d/%d", filled, total))
		case:SetAttribute(Config.CompletedAttribute, complete)
	end

	broadcast(case, filled, total, complete)

	if complete and not rec.completed then
		rec.completed = true
		local ev = events[case]
		if ev then
			ev:Fire(filled, total)
		end
		Config.log("PUZZLE COMPLETE:", case:GetFullName())
	end
end

-- ============================================================
-- REGISTER
-- ============================================================

local function registerCase(case: Instance)
	if cases[case] then
		return
	end
	cases[case] = { completed = false }
	events[case] = ensureEvent(case)
	Config.log("registered case for puzzle", case:GetFullName())
end

local function unregisterCase(case: Instance)
	cases[case] = nil
	local ev = events[case]
	if ev then
		ev:Destroy()
	end
	events[case] = nil
end

function PuzzleService.start()
	for _, case in ipairs(CollectionService:GetTagged(Config.CaseTag)) do
		registerCase(case)
	end
	CollectionService:GetInstanceAddedSignal(Config.CaseTag):Connect(registerCase)
	CollectionService:GetInstanceRemovedSignal(Config.CaseTag):Connect(unregisterCase)
	Config.log("PuzzleService started")
end

return PuzzleService
