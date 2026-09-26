460| 		humanoid.Health = 100
461| 	elseif humanoid.Health <= 0 then
462| 		warn("[MonsterAI] " .. monsterModel.Name .. ": Health=0 saat init (NPC mati) -> AI tidak akan jalan. Diperbaiki otomatis ke MaxHealth.")
463| 		humanoid.Health = humanoid.MaxHealth
464| 	end
465| 	for _, problem in Config.validateOverrides(monsterModel) do
466| 		warn("[MonsterAI] " .. monsterModel.Name .. ": " .. problem)
467| 	end
468| 	-- Setup Humanoid
469| 	humanoid.WalkSpeed = Config.get(monsterModel, "PatrolSpeed")
470| 	humanoid.AutoRotate = true
471| 	-- Tentukan chase mode: Attribute per-monster > default Config.
472| 	-- Attribute "ChaseMode" (string) di Model monster meng-override default.
473| 	local modeAttr = monsterModel:GetAttribute("ChaseMode")
474| 	local chaseMode = (typeof(modeAttr) == "string" and modeAttr ~= "") and modeAttr or Config.ChaseMode
475| 	if chaseMode ~= "PERSISTENT" and chaseMode ~= "NEAREST" and chaseMode ~= "ITEM_HOLDER" then
476| 		warn("[MonsterAI] ChaseMode '" .. tostring(chaseMode) .. "' tidak dikenal pada " .. monsterModel.Name .. ". Fallback ke NEAREST.")
477| 		chaseMode = "NEAREST"
478| 	end
479| 	local rig = MonsterRig:setup(monsterModel)
480| 	if rig.error then
481| 		warn("[MonsterAI] " .. monsterModel.Name .. ": setup rig gagal -> " .. tostring(rig.error))
482| 	else
483| 		print(string.format(
484| 			"[MonsterAI] %s: rig siap (proxy=%s, collider=%s, HipHeight=%s, mesh diputar=%s, AnimationController dibuang %s%s)",
485| 			monsterModel.Name,
486| 			rig.proxyCreated and "dibuat" or "sudah ada",
487| 			rig.colliderSize and string.format("%.0fx%.0fx%.0f", rig.colliderSize.X, rig.colliderSize.Y, rig.colliderSize.Z) or "-",
488| 			rig.hipHeight and string.format("%.2f", rig.hipHeight) or "-",
489| 			tostring(rig.rotatedMesh == 1),
490| 			tostring(rig.animControllerRemoved),
491| 			#rig.scriptsDisabled > 0 and (", script dimatikan: " .. table.concat(rig.scriptsDisabled, " ")) or ""
492| 		))
493| 	end
494| 	-- Kanal publikasi ke script NPC (animasi, SFX, VFX, dll)
495| 	local signal = ensureSignal(monsterModel)
496| 	signal.Event:Connect(function(eventName, targetChar)
497| 		if eventName == "Jumpscare" and targetChar then
498| 			local player = Players:GetPlayerFromCharacter(targetChar)
499| 			if player then
500| 				local jumpscareEvent = game:GetService("ReplicatedStorage"):FindFirstChild("JumpscareEvent")
501| 				if jumpscareEvent then
502| 					-- Tembak event hanya ke pemain yang mati/ditangkap
503| 					jumpscareEvent:FireClient(player, monsterModel)
504| 				end
505| 			end