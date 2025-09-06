---@class LibRTC : AceAddon
local LibRTC = LibStub('AceAddon-3.0'):NewAddon('Libs-RemixPowerLevel')

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

function LibRTC:OnEnable()
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
