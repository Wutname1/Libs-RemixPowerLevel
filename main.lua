---@class LibRTC : AceAddon
local LibRTC = LibStub('AceAddon-3.0'):NewAddon('Libs-RemixThreadCount')

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

---@param self any
local function TooltipProcessor(self)
	local _, unit = self:GetUnit()
	if not unit then
		return
	end
	local cloakData = C_UnitAuras.GetAuraDataBySpellName(unit, "Timerunner's Advantage")
	if cloakData ~= nil then
		local total = 0
		for i = 1, 9 do
			total = total + cloakData.points[i]
		end
		self:AddLine('\n|cff00FF98Threads |cffFFFFFF' .. comma_value(total))
	end
end

---@param button any
---@param unit UnitId
local function UpdateItemSlotButton(button, unit)
	local slotID = button:GetID()

	if slotID >= INVSLOT_FIRST_EQUIPPED and slotID <= INVSLOT_LAST_EQUIPPED then
		if IsTimerunnerMode() then
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
			-- Create overlay frame if it doesn't exist
			if not button.ThreadCountOverlay then
				local overlayFrame = CreateFrame('FRAME', nil, button)
				overlayFrame:SetAllPoints()
				overlayFrame:SetFrameLevel(button:GetFrameLevel() + 1)
				button.ThreadCountOverlay = overlayFrame
			end

			if string.match(item:GetItemName() or '', 'Cloak of Infinite Potential') then
				local c, ThreadCount = {0, 1, 2, 3, 4, 5, 6, 7, 148}, 0
				for i = 1, 9 do
					ThreadCount = ThreadCount + C_CurrencyInfo.GetCurrencyInfo(2853 + c[i]).quantity
				end
				-- print('Total threads updated: ' .. ThreadCount)
				if not button.threadCount then
					button.threadCount = button.ThreadCountOverlay:CreateFontString('$parentItemLevel', 'OVERLAY')
					button.threadCount:SetFont('fonts/arialn.ttf', 13, '')
					button.threadCount:ClearAllPoints()
					button.threadCount:SetPoint('LEFT', button.ThreadCountOverlay, 'RIGHT', 2, 0)
				end
				button.threadCount:SetFormattedText('|cff00FF98Threads:|cffFFFFFF\n' .. comma_value(ThreadCount))
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
