-- Add a button to the craft (enchant) frame to search the AH for the reagents.
-- The button will be hidden when the AH is closed.
-- The total price is shown in a FontString next to the button
local addedFunctionality = false
function Auctionator.EnchantInfo.Initialize()
  if addedFunctionality then
    return
  end

  if CraftFrame then
    addedFunctionality = true

    CreateFrame("Frame", "AuctionatorEnchantInfoFrame", CraftFrame, "AuctionatorEnchantInfoFrameTemplate");
  end
end

function Auctionator.EnchantInfo.DoCraftReagentsSearch()
  local craftIndex = GetCraftSelectionIndex()
  local craftInfo =  { GetCraftInfo(craftIndex) }

  local items = {craftInfo[1]}

  for reagentIndex = 1, GetCraftNumReagents(craftIndex) do
    local reagentName = GetCraftReagentInfo(craftIndex, reagentIndex)
    table.insert(items, reagentName)
  end

  Auctionator.API.v1.MultiSearch(AUCTIONATOR_L_REAGENT_SEARCH, items)
end

function Auctionator.EnchantInfo.GetCraftReagentsTotal()
  local craftIndex = GetCraftSelectionIndex()

  local total = 0

  for reagentIndex = 1, GetCraftNumReagents(craftIndex) do
    local multiplier = select(3, GetCraftReagentInfo(craftIndex, reagentIndex))
    local link = GetCraftReagentItemLink(craftIndex, reagentIndex)
    if link ~= nil then
      local itemID = tonumber(link:match("item:(%d+)"))
      local unitPrice
      
      -- Special case for Blood of Heroes
      if itemID == 12938 then
        unitPrice = Auctionator.Constants.BLOOD_OF_HEROES_COST
      else
        local vendorPrice = Auctionator.API.v1.GetVendorPriceByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, link)
        local auctionPrice = Auctionator.API.v1.GetAuctionPriceByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, link)
        unitPrice = vendorPrice or auctionPrice
      end

      if unitPrice ~= nil then
        total = total + multiplier * unitPrice
      end
    end
  end

  return total
end

function Auctionator.EnchantInfo.GetFee(craftCost)
  -- Fee is the maximum of 5 gold or 15% of the To Craft cost
  local fifteenPercent = craftCost * Auctionator.Constants.FEE_PERCENTAGE
  
  return math.max(Auctionator.Constants.MINIMUM_FEE, fifteenPercent)
end

function Auctionator.EnchantInfo.GetSellPrice(craftCost, fee)
  -- To Sell is To Craft plus Fee, rounded to the nearest gold
  local total = craftCost + fee
  local goldValue = math.floor(total / 10000) -- Convert to gold
  
  -- Round to nearest gold
  local remainder = total % 10000
  if remainder >= 5000 then
    goldValue = goldValue + 1
  end
  
  return goldValue * 10000 -- Convert back to copper
end

function Auctionator.EnchantInfo.GetInfoText()
  if Auctionator.Config.Get(Auctionator.Config.Options.CRAFTING_INFO_SHOW_COST) then
    local craftCost = Auctionator.EnchantInfo.GetCraftReagentsTotal()
    local price = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(craftCost, true))
    local result = AUCTIONATOR_L_TO_CRAFT_COLON .. " " .. price
    
    local fee = Auctionator.EnchantInfo.GetFee(craftCost)
    local feePrice = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(fee, true))
    result = result .. "\n" .. AUCTIONATOR_L_FEE_COLON .. " " .. feePrice
    
    local sellPrice = Auctionator.EnchantInfo.GetSellPrice(craftCost, fee)
    local sellPriceText = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(sellPrice, true))
    result = result .. "\n" .. AUCTIONATOR_L_TO_SELL_COLON .. " " .. sellPriceText
    
    return result
  else
    return ""
  end
end
