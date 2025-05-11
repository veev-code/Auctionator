-- Add a button to the tradeskill frame to search the AH for the reagents.
-- The button will be hidden when the AH is closed.
-- The total price is shown in a FontString next to the button
local addedFunctionality = false
function Auctionator.CraftingInfo.Initialize()
  if addedFunctionality then
    return
  end

  if TradeSkillFrame then
    addedFunctionality = true
    CreateFrame("Frame", "AuctionatorCraftingInfo", TradeSkillFrame, "AuctionatorCraftingInfoFrameTemplate");
  end
end

-- Get the associated item, spell level and spell equipped item class for an
-- enchant
local function EnchantLinkToData(enchantLink)
  return Auctionator.CraftingInfo.EnchantSpellsToItemData[tonumber(enchantLink:match("enchant:(%d+)"))]
end

local function GetOutputName(callback)
  local recipeIndex = GetTradeSkillSelectionIndex()
  local outputLink = GetTradeSkillItemLink(recipeIndex)
  local itemID

  if outputLink then
    itemID = C_Item.GetItemInfoInstant(outputLink)
  else -- Probably an enchant
    local data = EnchantLinkToData(GetTradeSkillRecipeLink(recipeIndex))
    if data == nil then
      callback(nil)
      return
    end
    itemID = data.itemID
  end

  if itemID == nil then
    callback(nil)
    return
  end

  local item = Item:CreateFromItemID(itemID)
  if item:IsItemEmpty() then
    callback(nil)
  else
    item:ContinueOnItemLoad(function()
      callback(item:GetItemName())
    end)
  end
end

function Auctionator.CraftingInfo.DoTradeSkillReagentsSearch()
  GetOutputName(function(outputName)
    local items = {}
    if outputName then
      table.insert(items, {searchString = outputName, isExact = true})
    end
    local recipeIndex = GetTradeSkillSelectionIndex()

    for reagentIndex = 1, GetTradeSkillNumReagents(recipeIndex) do
      local reagentName, _, count = GetTradeSkillReagentInfo(recipeIndex, reagentIndex)
      table.insert(items, {searchString = reagentName, quantity = count, isExact = true})
    end

    Auctionator.API.v1.MultiSearchAdvanced(AUCTIONATOR_L_REAGENT_SEARCH, items)
  end)
end

local function GetSkillReagentsTotal()
  local recipeIndex = GetTradeSkillSelectionIndex()

  local total = 0

  for reagentIndex = 1, GetTradeSkillNumReagents(recipeIndex) do
    local multiplier = select(3, GetTradeSkillReagentInfo(recipeIndex, reagentIndex))
    local link = GetTradeSkillReagentItemLink(recipeIndex, reagentIndex)
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

local function GetEnchantProfit()
  local toCraft = GetSkillReagentsTotal()

  local recipeIndex = GetTradeSkillSelectionIndex()
  local data = EnchantLinkToData(GetTradeSkillRecipeLink(recipeIndex))
  if data == nil then
    return nil
  end

  -- Find the cheapest vellum that will work
  local vellumCost = Auctionator.API.v1.GetVendorPriceByItemID(AUCTIONATOR_L_REAGENT_SEARCH, Auctionator.Constants.EnchantingVellumID) or 0

  local currentAH = Auctionator.API.v1.GetAuctionPriceByItemID(AUCTIONATOR_L_REAGENT_SEARCH, data.itemID)
  if currentAH == nil then
    currentAH = 0
  end
  local age = Auctionator.API.v1.GetAuctionAgeByItemID(AUCTIONATOR_L_REAGENT_SEARCH, data.itemID)
  local exact = Auctionator.API.v1.IsAuctionDataExactByItemID(AUCTIONATOR_L_REAGENT_SEARCH, data.itemID)

  return math.floor(currentAH * Auctionator.Constants.AfterAHCut - vellumCost - toCraft), age, currentAH ~= 0, exact
end

local function GetAHProfit()
  local recipeIndex = GetTradeSkillSelectionIndex()

  if select(5, GetTradeSkillInfo(recipeIndex)) == ENSCRIBE then
    return GetEnchantProfit()
  end

  local recipeLink =  GetTradeSkillItemLink(recipeIndex)
  local count = GetTradeSkillNumMade(recipeIndex)

  if recipeLink == nil or recipeLink:match("enchant:") then
    return nil
  end

  local currentAH = Auctionator.API.v1.GetAuctionPriceByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, recipeLink)
  if currentAH == nil then
    currentAH = 0
  end
  local age = Auctionator.API.v1.GetAuctionAgeByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, recipeLink)
  local exact = Auctionator.API.v1.IsAuctionDataExactByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, recipeLink)
  local toCraft = GetSkillReagentsTotal()

  return math.floor(currentAH * count * Auctionator.Constants.AfterAHCut - toCraft), age, currentAH ~= 0, exact
end

local function CraftCostString()
  local price = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(GetSkillReagentsTotal(), true))

  return AUCTIONATOR_L_TO_CRAFT_COLON .. " " .. price
end

local function ProfitString(profit)
  local price
  if profit >= 0 then
    price = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(profit, true))
  else
    price = RED_FONT_COLOR:WrapTextInColorCode("-" .. GetMoneyString(-profit, true))
  end

  return AUCTIONATOR_L_PROFIT_COLON .. " " .. price

end

local function GetFee(craftCost)
  -- Fee is the maximum of 5 gold or 15% of the To Craft cost
  local fifteenPercent = craftCost * Auctionator.Constants.FEE_PERCENTAGE
  
  return math.max(Auctionator.Constants.MINIMUM_FEE, fifteenPercent)
end

local function GetSellPrice(craftCost, fee)
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

local function FeeString(craftCost)
  local fee = GetFee(craftCost)
  local price = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(fee, true))

  return AUCTIONATOR_L_FEE_COLON .. " " .. price
end

local function SellPriceString(craftCost, fee)
  local sellPrice = GetSellPrice(craftCost, fee)
  local price = WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(sellPrice, true))

  return AUCTIONATOR_L_TO_SELL_COLON .. " " .. price
end

local function IsEnchantingRecipe()
  local recipeIndex = GetTradeSkillSelectionIndex()
  return select(5, GetTradeSkillInfo(recipeIndex)) == ENSCRIBE
end

function Auctionator.CraftingInfo.GetInfoText()
  local result = ""
  local lines = 0
  
  if Auctionator.Config.Get(Auctionator.Config.Options.CRAFTING_INFO_SHOW_COST) then
    local craftCost = GetSkillReagentsTotal()
    
    if lines > 0 then
      result = result .. "\n"
    end
    result = result .. CraftCostString()
    lines = lines + 1
    
    -- Check if this is an enchanting recipe
    local isEnchanting = IsEnchantingRecipe()
    
    -- Add Fee and To Sell if this is an enchanting recipe
    if isEnchanting then
      -- Add Fee line
      result = result .. "\n" .. FeeString(craftCost)
      lines = lines + 1
      
      -- Add To Sell line
      result = result .. "\n" .. SellPriceString(craftCost, GetFee(craftCost))
      lines = lines + 1
    end
  end

  if Auctionator.Config.Get(Auctionator.Config.Options.CRAFTING_INFO_SHOW_PROFIT) then
    local profit, age, anyPrice, exact = GetAHProfit()

    if profit ~= nil then
      if lines > 0 then
        result = result .. "\n"
      end
      result = result .. ProfitString(profit) .. Auctionator.CraftingInfo.GetProfitWarning(profit, age, anyPrice, exact)
      lines = lines + 1
    end
  end
  return result, lines
end
