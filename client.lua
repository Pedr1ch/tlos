-- //User: Pedro
-- //Lua v5.3
-- //Desc. Main Branch
-- //D:/LuaProjects/TLOS/v1035/client/sps/client.lua
-- // UNC path: ///.//GLOBALROOT/Device/HarddiskVolume5/$INDEX_ALLOCATION/LuaProjects/TLOS/v1035/client/sps/client.lua

--not strict
-- // command former
--[[
	bash
    src -install
    src -run
    src\> start options=[ver="1035", dir=`/client/sps/client.lua`]
    src\> quit
]]


-- VARIABLES --
local ModulesFolder = game.ReplicatedStorage.modules
local Modules = require(ModulesFolder.modules)
local Network = Modules.network
local UtilSignals = ModulesFolder.modules.network["utilSignals.disabled"]
local NetworkProxyMapping = require(ModulesFolder.modules.network.proxyMapping)
local Signals = require(ModulesFolder.modules.network.signals)
local player = game.Players.LocalPlayer
local Controllers = script.Parent:WaitForChild('Controllers')
local ControllerModule = require(Controllers.Controller)
local signalsModule = ModulesFolder.modules.network.signals
-- SHARED -- SOURCE
local self = {}
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')
local StarterGui = game:GetService('StarterGui')
local RunService = game:GetService('RunService')
local HttpService = game:GetService('HttpService')
local TweenService = game:GetService('TweenService')
local ChatService = game:GetService('Chat')
local ContextActionService = game:GetService('ContextActionService')
local LocalizationService = game:GetService('LocalizationService')
local Utilities = ReplicatedStorage.utilityModules
local Communication = require(Utilities.communication)
local ArrayMethods = require(Utilities.arrayUtil)
local PlatinumAbbreviation = require(Utilities.platinumAbbreviation)
local iterate = require(Utilities.iterator)
local foreachi = table.foreachi
local BubbleChatEnabled = true
local CustomBubbleChat = true
local ChatModules = ChatService.ChatModules or wait(1)
ChatModules = ChatService.ChatModules
--local ProximityChatModules = ChatService.ProximityChatModules
local ChatModulesUtilities = ChatModules.Utility
local ClientChatModules = ChatService.ClientChatModules
local ChatLocalizationLanguageSetting = ChatService.ChatLocalization.SourceLocaleId
local LocalizationTranslator = LocalizationService:GetTranslatorForPlayer(player)
local ChatConstants = require(ClientChatModules.ChatConstants)--wait
local ChatSettings = require(ClientChatModules.ChatSettings)--wait
local ChatLocalization = require(ClientChatModules.ChatLocalization)--wait
local PlayerGui = player.PlayerGui
local Insert = table.insert
local gsub = string.gsub
local sub = string.sub
local find = string.find
local len = string.len
local format = string.format
local ColcheteSubber = "[%s]"
local pi = math.pi
local clamp = math.clamp
local random = math.random
local rad = math.rad
local huge = math.huge
local max = math.max
local min = math.min
local minNumber = -huge
local maxNumber = huge
local inputModule = require(ReplicatedStorage.modules.inputLookup)
local Stats = require(ReplicatedStorage.modules.stats)
local Quests = require(ReplicatedStorage.modules.questsLookup)
local Repr = require(ReplicatedStorage.modules.repr)
local Network = require(ReplicatedStorage.modules.modules.network)
local DataModule = require(ReplicatedStorage.modules.dataLookup)
local PLAYER_SESSION_CLSID = HttpService:GenerateGUID(true)
local ControllersFolder = script.Parent.Controllers
local Controllers = require(Controllers.Controller)
local callServerAlternative = Controllers.CommunicationController.CallServerRemotely

local armor = nil
local weapon
if len(PLAYER_SESSION_CLSID) >= 10 then
	local CLSID = Instance.new('StringValue')
	CLSID.Value = PLAYER_SESSION_CLSID
	CLSID.Name = "PlayerSessionClsid"
	CLSID.Parent = player
end
local function call_server(way: string, ...)
	local args = ...
	if ReplicatedStorage[way] ~= nil then
		if ReplicatedStorage[way]:IsA("RemoteFunction") then
			return ReplicatedStorage[way]:InvokeServer(args)
		else
			return ReplicatedStorage[way]:FireServer(args)
		end
	end
end
--local Data = call_server("playerDataRemote")

type dataStructure = {}
local function checkData(data)
	if data then
		return data
	else
		return nil
	end
end

local stringToTable = function(s) 
	-- deprecated return loadstring("return ".. s)
end
local playerData = Signals.invokeServer(signalsModule.getPlayerData_Signal)
if checkData(playerData) == nil then
	error("NO DATA, GAME CANT INTIALISE :(")
end
local mainGuiBranch = PlayerGui:WaitForChild('main')
local gold = mainGuiBranch.gold
--local version = mainGuiBranch.version
local platinum = mainGuiBranch.platinum
local util = require(script.util)
for i, v in pairs(mainGuiBranch:GetChildren()) do
	if v:IsA("TextButton") or v:IsA("GuiButton") then
		local e = v.Name
		local inputClient = ModulesFolder.inputLookup[inputModule.client()]
		local openKey = string.upper(string.sub(e,0,1)) .. string.sub(e, 2, e:len()) .. "OpenKey"
		v:WaitForChild("key").Text = require(inputClient).Keybinds[openKey].Name
		
		v.MouseButton1Click:Connect(function()
			if v.Name == 'stats' then
				util.StatsOpenKeyFired()
			elseif v.Name == 'settings' then
				util.SettingsOpenKeyFired()
			else
				util.InventoryOpenKeyFired()
			end
		end)
		UserInputService.InputBegan:Connect(function(input, chatting)
			if chatting == true then
				return
			end
			if input.KeyCode == require(inputClient).Keybinds[openKey] and v.Name == 'stats' then
				util.StatsOpenKeyFired()
			elseif v.Name == 'settings' and input.KeyCode ==require(inputClient).Keybinds[openKey]  then
				util.SettingsOpenKeyFired()
			elseif v.Name == 'inventory' and input.KeyCode ==require(inputClient).Keybinds[openKey] then
				util.InventoryOpenKeyFired()
			end
		end)
	    
	end
end
local canDash = true
UserInputService.InputBegan:Connect(function(input, Typing)
	if input.KeyCode == Enum.KeyCode.Q and canDash and Typing == false then
		local character = player.Character
		local LookVector = character.HumanoidRootPart.CFrame.LookVector
		local animDash = character.Humanoid:LoadAnimation(game.ReplicatedStorage.player_dash)
        
        game.ReplicatedStorage.sounds.snd_dash:Play()
		animDash:Play()
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.51, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0,false,0), {FieldOfView = 90}):Play()
		TweenService:Create(character.HumanoidRootPart, TweenInfo.new(0.51, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0,false,0), {CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 0, LookVector.Z - 25)}):Play()
		wait(.25)
		character.HumanoidRootPart.CFrame *= CFrame.new(0, 0, LookVector.Z - 25)
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.51, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0,false,0), {FieldOfView = 70}):Play()
		canDash = false
		animDash.Stopped:Connect(function()
			wait(3) canDash = true
		end)  
	end
	if input.KeyCode == Enum.KeyCode.LeftShift and Typing == false then
		local character, Humanoid = game.Players.LocalPlayer.Character, player.Character.Humanoid
		Humanoid.WalkSpeed = 22
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.51, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0,false,0), {FieldOfView = 90}):Play()
		local anim = Humanoid:LoadAnimation(game.ReplicatedStorage.characterAnimations.player_run)
		while wait() do
			if Typing == true then
				local function isKeyDown_(Keys: {string?})
					for i,v in pairs(Keys) do
						if UserInputService:IsKeyDown(v) then
							return true
						else
							if i==#Keys then
								return false
							end
						end
					end
				end
				local isKeyDown_Mov = function()
					if UserInputService:IsKeyDown("W") or UserInputService:IsKeyDown("A") or UserInputService:IsKeyDown("S") or UserInputService:IsKeyDown("D") then
						return true
					else
						return false
					end
				end
				
				if UserInputService:IsKeyDown("LeftShift") and isKeyDown_Mov() then
					anim:Play()
				elseif UserInputService:IsKeyDown("LeftShift") and isKeyDown_Mov() == false then
					anim:Stop()
				end
			else
			end

		end

	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and Typing == false then
		local function slashOn()
			local canslash = true
			if weapon ~= "Null Weapon" then
				if canslash == "now slashing" then
					return
				end
				local playerWeaponManifest = nil
			    canslash = "now slashing"
				for i, v in pairs(player.Character:GetChildren()) do
					if v.Name:find("Hair") then
					else
						if v:IsA("Accessory") and ReplicatedStorage.modules.itemData[v.Name] ~= nil and require(ReplicatedStorage.modules.itemData[v.Name]).manifestType:lower() == "weapon" then
							playerWeaponManifest = v
							break
						else

						end
					end

				end
				local weaponRequireSource = require(ReplicatedStorage.modules.itemData[playerWeaponManifest.Name])
				local weaponDamage = require(ReplicatedStorage.modules.itemData[playerWeaponManifest.Name]).points
				local weaponTier = weaponRequireSource.tier
				local tierBonuses = {
					Common = nil,
					Uncommon = "ATK:10%",
					Rare = "ATK:20%",
					Epic = "ATK:30%;EnableHideoutAccess:1",
					Legendary = "ATK:40%",
					Exotic = "ATKX:1.5;ALLSTATP:2",
					Mythical = "ATKX:3;ALLSTATP:5"
				}
				local tierBonusesDictionary = {
					ATK = function(dispatch: string, formalStat: number)
						local numMethods = require(ReplicatedStorage.utilityModules.numUtil)
						local dispatchPercentage = dispatch:gsub(":", ''):gsub("%%",'')
						local dispatchStat = formalStat / 100
						-- atk:160, dispatch: 30
						return (dispatchStat * dispatchPercentage)
					end,
					EnableHideoutAccess = function(dispatch: string)
						
					end,
					ATKX = function(dispatch: string)
						
					end,
					ALLSTATP = function(dispatch: string)
						
					end,
				}
				local ontouchconnection = playerWeaponManifest.Handle.Touched:Connect(function(otherPart)
					local enemies = ReplicatedStorage.entities
					for i,v in pairs(enemies:GetChildren()) do
						if otherPart.Parent.Name == v.Name then
							local enemy = otherPart.Parent
							local ATK = game.Players.LocalPlayer.Stats.ATK.Value
							local level = player.NumberPrincipals.Level.Value
							if ATK then
								local damageCompute = require(ModulesFolder.stats.atk)
								local damage = damageCompute.Functions.ComputeNewDmgAspect(weaponDamage, ATK, level)
								enemy.Humanoid.Health -= weaponDamage
							end
						end
					end
                     
				end)
				
				local slashAnim = player.Character.Humanoid:LoadAnimation(game.ReplicatedStorage.characterAnimations.player_slash)
				slashAnim:Play()
				ontouchconnection:Disconnect()
				wait(.8)
				canslash = true
			else
				
			end
		end
		slashOn()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		local character, Humanoid = game.Players.LocalPlayer.Character, player.Character.Humanoid
		Humanoid.WalkSpeed = 16
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.51, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0,false,0), {FieldOfView = 70}):Play()
		local runAnim = Humanoid:LoadAnimation(game.ReplicatedStorage.characterAnimations.player_run)
		runAnim:Stop()

	end
end)


--Cmdr Data Setup
repeat
	wait()
	warn("Waiting for CMDR Administrative")
until ReplicatedStorage.CmdrClient
local Cmdr = ReplicatedStorage.CmdrClient
local CmdrSetupRequire = require(Cmdr)
if game.Players.LocalPlayer.Name == "Phroaguz" or "cafcover" or "Jibanyan1220" or "Kuncheon1" or "freezegirl1114" then
	CmdrSetupRequire:SetActivationKeys({ Enum.KeyCode.F2 }) --> F2:ACTIVATE
end

--camera
local camera = workspace.CurrentCamera
local isCamLocked = false
local canLockCam = true
UserInputService.InputBegan:Connect(function(input, typing)
	self.inputRelated__action__lockCamera = function(input: InputObject, typing: boolean) --> @@ REQUIRES INPUT AND TYPING PARAMETERS GIVEN AT INPUTBEGAN CONNECTION @@
		if typing == false and input.KeyCode == Enum.KeyCode.RightShift then
			local camLockfuncs = {
				__desktop = function(...)
					local arguments = ...
					if canLockCam and isCamLocked == false then
						UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter --> @@ SL SYNONYM ENABLER
						
						isCamLocked = true
					elseif canLockCam and isCamLocked then
						UserInputService.MouseBehavior = Enum.MouseBehavior.Default
						isCamLocked = false
					end
				end,
				__mobile = function(...)
					local arguments = ...
				end,
				__console = function(...)
					local arguments = ...
				end,
			}-- @@ FUNCTIONS RELATED TO CAM LOCK @@
			camLockfuncs[inputModule.client()]() -- @@ CALLER: FINDS THE CAM LOCK FUNCTION FOR EACH CLIENT @@
		end
	end
	
    self.inputRelated__action__lockCamera(input, typing)
end)
-- @@STATS@@
local StatsFrame = mainGuiBranch.statsFrame
for i,v in pairs(StatsFrame:GetChildren()) do
	if v:IsA('TextButton') then
		v.MouseButton1Click:Connect(function()
			local STATIncreasePoints = playerData.BuildExpecifications.AvaibleSkillPoints
			local Stat = v.Name:gsub('inc', '')
			if STATIncreasePoints >= 1 then
				local function call_server(way: string, ...)
					local args = ...
					if ReplicatedStorage[way] ~= nil then
						if ReplicatedStorage[way]:IsA("RemoteFunction") then
							return ReplicatedStorage[way]:InvokeServer(args)
						else
							return ReplicatedStorage[way]:FireServer(args)
						end
					end
				end
				Signals.fireServer(signalsModule.playerIncreasedStat_Signal, Stat, 1)
			else

			end
		end)
	end
end

local totalFrames = 0
RunService.RenderStepped:Connect(function()
	totalFrames += 1
	script.Parent.Controllers.ReactCompositions.TRF.Value = totalFrames + 0.052 --> @@ TOTAL RENDERED FRAMES DEBUG INFORMATION
	-- DEPURATION GUARANTEED! @@
	
end)
local function updateStats()
	for i,v in pairs(StatsFrame:GetChildren()) do
		-- @@ 1 IF? :happiness:
		if v.Name == "Title" or "avaiblePoints" then
		else
			v.Text = v.Name .. ": " .. player.Stats[v.Name].Value
		end --> @@ONLY VERIF? SUS

	end
end
local function updateGold()
	--.Text = "v" .. ReplicatedStorage.Version.Value
	gold.Text = "Gold: " .. player.NumberPrincipals.Gold.Value
end
local function nilCheck(a)
	local s, e = pcall(function()
		assert(a, "Does not exist.")
	end)
	if s then
		return true
	end
end

local firstTimeUpdateArmorTickLoadedCheckerBool = true
local function updateArmor()
	for i,v in pairs(player.Character:GetChildren()) do
		if v:IsA("Model") then
			if v:FindFirstChildWhichIsA("Weld") then
				Signals.fireServer(ModulesFolder.modules.network.signals.playerSettedArmorValue_Signal)
			end
		end
	end
	if armor == nil then
		armor = game.Players.LocalPlayer.Armor.Value
	else
		if firstTimeUpdateArmorTickLoadedCheckerBool == true then
			wait(.5)
		end
		local inventory = mainGuiBranch.inventoryFrame
		player:WaitForChild("Armor")
		local armorName = game.Players.LocalPlayer.Armor.Value
		local armorFrame = inventory.Separated.Armor
		local armorRarity = require(ReplicatedStorage.modules.itemData[armorName]).tier
		armorFrame.Rarity.Text = armorRarity
	
		armorFrame.Armor.Image = game.ReplicatedStorage.images[armorName].Image
		armorFrame:WaitForChild('Name').Text = armorName
	end
	firstTimeUpdateArmorTickLoadedCheckerBool = false
end
local inventory = mainGuiBranch.inventoryFrame
local armorFrame = inventory.Separated.Armor
local armorName = game.Players.LocalPlayer.Armor.Value
local armorRarity = require(ReplicatedStorage.modules.itemData[armorName]).tier
local armorHitbox = armorFrame.Hitbox
armorHitbox.MouseButton2Click:Connect(function()
	local mouseController = Controllers.MouseController
	local viewSize = mouseController.GetScreenSize:Invoke()
	local viewSizeX, viewSizeY = viewSize[1], viewSize[2]
	local mouseX, mouseY = mouseController.GetMouseXPos:Invoke(), mouseController.GetMouseYPos:Invoke()
	local mouseAspectRatioX, mouseAspectRatioY = mouseX / viewSizeX, mouseY / viewSizeY
	local DividableAR = mouseAspectRatioX + mouseAspectRatioY
	local DARMulti = (mouseX / mouseY) / DividableAR
	
	local UDimMousePosition = UDim2.new(-1,(mouseX) , -0.163,(mouseY))
	local informationTile = inventory.Separated.InformationTile
	informationTile.Position = UDimMousePosition
	informationTile.Visible = true
	informationTile.Close.MouseButton1Click:Connect(function()
		informationTile.Visible = false
	end)
	local equipOrUnequipTileConnection = informationTile.Equip.MouseButton1Click:Connect(function()
		if armorName == armorFrame:WaitForChild('Name').Text then
			Signals.fireServer(signalsModule.playerEquippedItem_Signal, armorName)
		else
			Signals.fireServer(signalsModule.playerUnequipItem_Signal, armorName)
		end
	end)
	local dropConnection = informationTile.Drop.MouseButton1Click:Connect(function()
		equipOrUnequipTileConnection:Disconnect()
		informationTile.Visible = false
		Signals.fireServer(signalsModule.playerDropItem_Signal, armorName)
	end)
end)
local firstTimeUpdateWeaponTickLoadedCheckerBool = true
local function updateWeapon()
	for i,v in pairs(player.Character:GetChildren()) do
		if v:IsA("Accessory") then
			if v:FindFirstChildWhichIsA("Weld") then
				Signals.fireServer(signalsModule.playerSettedWeaponValue_Signal, v.Name)
			end
		end
	end
	if weapon == nil then
		weapon = player.Weapon.Value
	else
		if firstTimeUpdateWeaponTickLoadedCheckerBool == true then
			wait(.5)
		end
		local inventory = mainGuiBranch.inventoryFrame
		player:WaitForChild("Weapon")
		local weaponName = game.Players.LocalPlayer.Weapon.Value
		local weaponFrame = inventory.Separated.Weapon
		local weaponRarity = require(ReplicatedStorage.modules.itemData[weaponName]).tier
		weaponFrame.Rarity.Text = weaponRarity

		weaponFrame.Weapon.Image = game.ReplicatedStorage.images[weaponName].Image
		weaponFrame:WaitForChild('Name').Text = weaponName
	end
	firstTimeUpdateWeaponTickLoadedCheckerBool = false
end
print("Loaded Client")
while true do
	wait(.1)
	repeat --> @@@@@@@@@@@@@@REPEAT LOOPS 180ms DELAY@@@@@@@@@@@@@
		wait(.08)
		updateStats()
		updateGold()
		updateArmor()
		updateWeapon()
	until script == nil
end
