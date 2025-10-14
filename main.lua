---@class LibRTC : AceAddon, AceEvent-3.0
local LibRTC = LibStub('AceAddon-3.0'):NewAddon('Libs-RemixPowerLevel', 'AceEvent-3.0')
local LDB = LibStub('LibDataBroker-1.1')
local LDBIcon = LibStub('LibDBIcon-1.0')

-- Initialize logger if Libs-AddonTools is available
if LibAT and LibAT.Logger then
	LibRTC.logger = LibAT.Logger.RegisterAddon('Libs-RemixPowerLevel')
else
	-- Fallback to print if logger not available
	LibRTC.logger = function(message)
		print('[Libs-RemixPowerLevel]', message)
	end
end

-- MOP: Timerunner's Advantage
-- Legion: Infinite Power

---@param value string
---@return string
local function comma_value(value)
	local left, num, right = string.match(value, '^([^%d]*%d)(%d*)(.-)$')
	return left .. (num:reverse():gsub('(%d%d%d)', '%1' .. (LARGE_NUMBER_SEPERATOR)):reverse()) .. right
end

---@return boolean
local function IsTimerunnerMode()
	return PlayerGetTimerunningSeasonID and PlayerGetTimerunningSeasonID() ~= nil
end

---@return boolean
local function IsMOPRemix()
	return IsTimerunnerMode() and PlayerGetTimerunningSeasonID() == 1
end

---@return boolean
local function IsLegionRemix()
	return IsTimerunnerMode() and PlayerGetTimerunningSeasonID() == 2
end

---@param self any
local function TooltipProcessor(self)
	-- Check if tooltip display is enabled
	if not LibRTC.db or not LibRTC.db.profile.showInTooltip then
		return
	end

	local _, unit = self:GetUnit()
	if not unit then
		return
	end

	-- MOP Remix: Check for Timerunner's Advantage (threads)
	if IsMOPRemix() then
		local cloakData = C_UnitAuras.GetAuraDataBySpellName(unit, "Timerunner's Advantage")
		if cloakData ~= nil then
			local total = 0
			for i = 1, 9 do
				total = total + cloakData.points[i]
			end
			self:AddLine('\n|cff00FF98Threads |cffFFFFFF' .. comma_value(total))
		end
	end

	-- Legion Remix: Check for Infinite Power
	if IsLegionRemix() then
		local powerData = C_UnitAuras.GetAuraDataBySpellName(unit, 'Infinite Power')
		if powerData ~= nil then
			local total = 0
			for i = 1, #powerData.points do
				total = total + powerData.points[i]
			end
			self:AddLine('\n|cff00FF00Aura Infinite Power |cffFFFFFF' .. comma_value(total))
		end
	end
end

---@param button any
---@param unit UnitId
local function UpdateItemSlotButton(button, unit)
	-- Check if character screen display is enabled
	if not LibRTC.db or not LibRTC.db.profile.showInCharacterScreen then
		-- Hide any existing displays
		if button.threadCount then
			button.threadCount:SetText('')
		end
		if button.infinitePowerCount then
			button.infinitePowerCount:SetText('')
		end
		return
	end

	local slotID = button:GetID()

	if slotID >= INVSLOT_FIRST_EQUIPPED and slotID <= INVSLOT_LAST_EQUIPPED then
		if IsTimerunnerMode() then
			-- Create overlay frame if it doesn't exist
			if not button.ThreadCountOverlay then
				local overlayFrame = CreateFrame('FRAME', nil, button)
				overlayFrame:SetAllPoints()
				overlayFrame:SetFrameLevel(button:GetFrameLevel() + 1)
				button.ThreadCountOverlay = overlayFrame
			end

			-- Handle MOP Remix (Cloak threads)
			if IsMOPRemix() then
				local item
				if unit == 'player' then
					item = Item:CreateFromEquipmentSlot(slotID)
				else
					local itemID = GetInventoryItemID(unit, slotID)
					local itemLink = GetInventoryItemLink(unit, slotID)
					if itemLink or itemID then
						item = itemLink and Item:CreateFromItemLink(itemLink) or Item:CreateFromItemID(itemID)
					end
				end

				if not item or item:IsItemEmpty() then
					return
				end

				if string.match(item:GetItemName() or '', 'Cloak of Infinite Potential') then
					local c, ThreadCount = {0, 1, 2, 3, 4, 5, 6, 7, 148}, 0
					for i = 1, 9 do
						ThreadCount = ThreadCount + C_CurrencyInfo.GetCurrencyInfo(2853 + c[i]).quantity
					end
					if not button.threadCount then
						button.threadCount = button.ThreadCountOverlay:CreateFontString('$parentItemLevel', 'OVERLAY')
						button.threadCount:SetFont('fonts/arialn.ttf', 13, '')
						button.threadCount:ClearAllPoints()
						button.threadCount:SetPoint('LEFT', button.ThreadCountOverlay, 'RIGHT', 2, 0)
					end
					button.threadCount:SetFormattedText('|cff00FF98Threads:|cffFFFFFF\n' .. comma_value(ThreadCount))
				end
			end

			-- Handle Legion Remix (Infinite Power buff above main weapon slot)
			if IsLegionRemix() and slotID == INVSLOT_MAINHAND and unit == 'player' then
				local powerData = C_UnitAuras.GetAuraDataBySpellName('player', 'Infinite Power')
				if powerData ~= nil then
					local total = 0
					for i = 1, #powerData.points do
						total = total + powerData.points[i]
					end
					if not button.infinitePowerCount then
						button.infinitePowerCount = button.ThreadCountOverlay:CreateFontString('$parentInfinitePower', 'OVERLAY')
						button.infinitePowerCount:SetFont('fonts/arialn.ttf', 13, '')
						button.infinitePowerCount:ClearAllPoints()
						button.infinitePowerCount:SetPoint('BOTTOM', button.ThreadCountOverlay, 'TOP', 10, 3)
					end
					button.infinitePowerCount:SetFormattedText('|cff00FF00Aura Infinite Power: |cffFFFFFF' .. comma_value(total))
				elseif button.infinitePowerCount then
					button.infinitePowerCount:SetText('')
				end
			elseif button.infinitePowerCount then
				button.infinitePowerCount:SetText('')
			end
		end
	end
end

---Get top 10 players by power level in group/raid
---@return table
local function GetTop10Players()
	local players = {}

	if not IsInGroup() then
		return players
	end

	local numMembers = GetNumGroupMembers()
	local isRaid = IsInRaid()

	for i = 1, numMembers do
		local unit = (isRaid and 'raid' or 'party') .. i
		if UnitExists(unit) then
			local name = UnitName(unit)
			local realm = GetRealmName()
			local fullName = name .. '-' .. realm
			local powerLevel = 0

			-- Check for MOP Remix threads
			if IsMOPRemix() then
				local cloakData = C_UnitAuras.GetAuraDataBySpellName(unit, "Timerunner's Advantage")
				if cloakData ~= nil then
					for i = 1, 9 do
						powerLevel = powerLevel + (cloakData.points[i] or 0)
					end
				end
			end

			-- Check for Legion Remix Infinite Power
			if IsLegionRemix() then
				local powerData = C_UnitAuras.GetAuraDataBySpellName(unit, 'Infinite Power')
				if powerData ~= nil then
					for i = 1, #powerData.points do
						powerLevel = powerLevel + (powerData.points[i] or 0)
					end
				end
			end

			if powerLevel > 0 then
				table.insert(players, {name = fullName, power = powerLevel})
			end
		end
	end

	-- Sort by power level descending
	table.sort(
		players,
		function(a, b)
			return a.power > b.power
		end
	)

	-- Return top 10
	local top10 = {}
	for i = 1, math.min(10, #players) do
		table.insert(top10, players[i])
	end

	return top10
end

---Setup options UI
local function GetOptions()
	return {
		name = "Lib's - Remix Power Level",
		type = 'group',
		get = function(info)
			return LibRTC.db.profile[info[#info]]
		end,
		set = function(info, value)
			LibRTC.db.profile[info[#info]] = value
		end,
		args = {
			description = {
				type = 'description',
				name = 'Display power level information for Timerunner characters (MOP Remix Threads / Legion Remix Infinite Power).',
				order = 1,
				fontSize = 'medium'
			},
			showInCharacterScreen = {
				type = 'toggle',
				name = 'Show in Character Screen',
				desc = 'Display thread count next to the Cloak of Infinite Potential (MOP) or Infinite Power above main weapon (Legion)',
				order = 10,
				width = 'full'
			},
			showInTooltip = {
				type = 'toggle',
				name = 'Show in Tooltip',
				desc = 'Display power level information in unit tooltips',
				order = 11,
				width = 'full'
			},
			minimapHeader = {
				type = 'header',
				name = 'Minimap Button',
				order = 20
			},
			minimapButton = {
				type = 'toggle',
				name = 'Show Minimap Button',
				desc = 'Display a minimap button that shows top 10 power levels in your group',
				order = 21,
				width = 'full',
				get = function()
					return not LibRTC.db.profile.minimap.hide
				end,
				set = function(_, value)
					LibRTC.db.profile.minimap.hide = not value
					if value then
						LDBIcon:Show('Libs-RemixPowerLevel')
					else
						LDBIcon:Hide('Libs-RemixPowerLevel')
					end
				end
			}
		}
	}
end

function LibRTC:OnInitialize()
	-- Setup database
	self.db =
		LibStub('AceDB-3.0'):New(
		'LibsRemixPowerLevelDB',
		{
			profile = {
				showInCharacterScreen = true,
				showInTooltip = true,
				minimap = {
					hide = false
				}
			}
		},
		true
	)

	-- Create options table for modules to extend
	self.OptTable = GetOptions()

	-- Register options with AceConfig
	LibStub('AceConfig-3.0'):RegisterOptionsTable('Libs-RemixPowerLevel', function() return self.OptTable end)
	LibStub('AceConfigDialog-3.0'):AddToBlizOptions('Libs-RemixPowerLevel', "Lib's - Remix Power Level")

	-- Create LibDataBroker object
	local ldbObject =
		LDB:NewDataObject(
		'Libs-RemixPowerLevel',
		{
			type = 'data source',
			text = 'Remix Power Level',
			icon = 'Interface/Addons/Libs-RemixPowerLevel/Logo-Icon',
			OnClick = function(clickedframe, button)
				if button == 'LeftButton' then
					-- Open Blizzard options to this addon
					Settings.OpenToCategory("Lib's - Remix Power Level")
				elseif button == 'RightButton' and IsShiftKeyDown() then
					-- Hide minimap button
					LibRTC.db.profile.minimap.hide = true
					LDBIcon:Hide('Libs-RemixPowerLevel')
					print('Libs-RemixPowerLevel: Minimap button hidden. Re-enable in addon options.')
				end
			end,
			OnTooltipShow = function(tooltip)
				if not IsTimerunnerMode() then
					tooltip:AddLine('|cffFFFFFFLibs - Remix Power Level|r')
					tooltip:AddLine('|cffFF0000Not in Timerunner mode|r')
					return
				end

				tooltip:AddLine('|cffFFFFFFLibs - Remix Power Level|r')
				tooltip:AddLine(' ')

				if not IsInGroup() then
					tooltip:AddLine('|cffFFAA00Not in a group|r')
					tooltip:AddLine(' ')
					tooltip:AddLine('|cff00FF00Left Click:|r Open Options')
					tooltip:AddLine('|cff00FF00Shift+Right Click:|r Hide Minimap Button')
					return
				end

				local top10 = GetTop10Players()

				if #top10 == 0 then
					tooltip:AddLine('|cffFFAA00No power levels detected|r')
				else
					tooltip:AddLine('|cff00FF98Top 10 Players:|r')
					for i, player in ipairs(top10) do
						tooltip:AddLine(string.format('%s |cffFFFFFF%s|r', comma_value(player.power), player.name))
					end
				end

				tooltip:AddLine(' ')
				tooltip:AddLine('|cff00FF00Left Click:|r Open Options')
				tooltip:AddLine('|cff00FF00Shift+Right Click:|r Hide Minimap Button')
			end
		}
	)

	-- Register minimap icon
	LDBIcon:Register('Libs-RemixPowerLevel', ldbObject, self.db.profile.minimap)

	-- Register slash command to open options
	SLASH_REMIXPOWERLEVEL1 = '/rpl'
	SLASH_REMIXPOWERLEVEL2 = '/remixpowerlevel'
	SlashCmdList['REMIXPOWERLEVEL'] = function()
		Settings.OpenToCategory("Lib's - Remix Power Level")
	end
end

function LibRTC:OnEnable()
	-- Log addon version/load for debugging
	if self.logger then
		self.logger.info("Libs-RemixPowerLevel loaded - commit e1e6085")
	end

	if IsTimerunnerMode() then
		-- Add tooltip processor
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, TooltipProcessor)

		-- Add item slot button update
		hooksecurefunc(
			'PaperDollItemSlotButton_Update',
			function(button)
				UpdateItemSlotButton(button, 'player')
			end
		)
	end
end
