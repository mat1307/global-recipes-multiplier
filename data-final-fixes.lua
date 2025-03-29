local mode = settings.startup["global-multiplier-nonint-mode"].value
local mult = settings.startup["global-multiplier-mult"].value
local multiply_time = settings.startup["global-multiplier-affects-time"].value
local ignore_barrels = settings.startup["global-multiplier-ignores-barrels"].value
local mult_energy = settings.startup["global-multiplier-mult-energy"].value
local all_items = data.raw["item"]
local all_modules = data.raw["module"]
local all_fluids = data.raw["fluid"]
local all_tools = data.raw["tool"]
local all_ammo = data.raw["ammo"]
local afeccts_categories = { "assembling-machine", "furnace", "lab", "agricultural-tower",
    "mining-drill", "radar" }



local function round(x)
    if mode == "roundup" then
        return math.ceil(x)
    elseif mode == "rounddown" then
        return math.floor(x)
    elseif mode == "roundeven" then
        return math.floor(x + 0.5)
    end
    return x
end


local function nilcheck(comparate)
    if not comparate then
        return true
    else
        return false
    end
end

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    else
        return value
    end
end

local function log_recipe_details(recipe, recipe_name)
    log("==== RECIPE: " .. recipe_name .. " ====")    
    -- Log basic properties
    log("  name: " .. (recipe_name or "nil"))
    log("  category: " .. (recipe.category or "nil"))
    log("  energy_required: " .. (recipe.energy_required or "nil"))
    
    -- Log if it uses 'result' format
    if recipe.result then
        log("  result: " .. recipe.result)
        log("  result_count: " .. (recipe.result_count or 1))
    end
    
    -- Log if it uses 'results' format
    if recipe.results then
        log("  results table:")
        for i, result in ipairs(recipe.results) do
            local result_info = "    [" .. i .. "] "
            if result.name then
                result_info = result_info .. "name: " .. result.name
                result_info = result_info .. ", type: " .. (result.type or "nil")
                result_info = result_info .. ", amount: " .. (result.amount or "nil")
                if result.amount_min then
                    result_info = result_info .. ", amount_min: " .. result.amount_min
                end
                if result.amount_max then
                    result_info = result_info .. ", amount_max: " .. result.amount_max
                end
            else
                -- Handle simplified format like {["copper-plate"] = 2}
                result_info = result_info .. "simplified format"
            end
            log(result_info)
        end
    end
    
    log("==== END RECIPE: " .. recipe_name .. " ====")
end

------------------------------------------------------------------------------
--[[
Value validation
Validates whether the item in question presents limitations and acts accordingly
]] --
------------------------------------------------------------------------------

local function amoutcheck(result, max, min, item, recipeName)
    recipeName = recipeName or "nil"
    if not result then
        log("Warning Element in recipe " .. recipeName .. " not affects")
        return
    end
    if nilcheck(max) and nilcheck(min) then
        --Evaluates whether there is no limit
        --or whether the limit is greater than the result of multiplying the element
        if not item.stack_size or not (round(result * mult) > item.stack_size) then
            return round(result * mult)
        else -- If there is a limit and the multiplication result is greater
            return item.stack_size
        end
    end

    -- If min or max are not defined, assign default values
    if nilcheck(max) then
        max = 999999
    end
    if nilcheck(min) then
        min = 1
    end
    -- returns the value of the multiplication limited between min and max
    return clamp(round(result * mult), max, min)
end
--Check if an item's flags include "non-stackable"
local function flagscheck(flags)
    if flags then
        for k, v in pairs(flags) do
            if v == "not-not-stackable" then
                return false
            end
        end
    end
    return true
end

--------------------------------------------------------------------------
--[[
Multiplies the amount of energy needed on an assembly machine,
only if this option is enabled.
]] --
---------------------------------------------------------------------------
if mult_energy ~= 1 then
    for _, category in pairs(afeccts_categories) do
        if data.raw[category] then
            for _, v in pairs(data.raw[category]) do
                if v and v.energy_source and v.energy_source.type == "electric" then
                    -- Separate letters and numbers within the energy use
                    local num = tonumber(v.energy_usage:match("%d+"))
                    local unidad = v.energy_usage:match("%a+")
                    if (round(num * mult_energy)) > 0 then
                        -- Multiplies the amount of energy used and reassigns it to the entity
                        v.energy_usage = (round(num * mult_energy)) .. unidad
                        log("Warning Energy usage in" .. v.name .. " now is " .. v.energy_usage)
                    else
                        log("Warning " .. v.name .. " not affects Energy changes")
                    end
                end
            end
        end
    end
else
    log("Warning Energy no modified")
end

-- For all recipes multiply the products
for _, v in pairs(data.raw.recipe) do
    log("Recipe : " .. v.name)
    -- Multiply the manufacturing time of a recipe
    if multiply_time and v.energy_required then
        v.energy_required = v.energy_required * mult
        --If a recipe does not have a manufacturing time, assign one
    elseif multiply_time and not v.energy_required then
        v.energy_required = 0.5 * mult
    end

    -- Skip barrel recipes if ignore_barrels is enabled
    if ignore_barrels and v.name:match("%-barrel$") then
        goto continue  -- Skip to next recipe
        log("Skipped recipe : " .. v.name)
    end

    if v.name == "speed-module" then
        log_recipe_details(v, v.name)
    end
    -- Handle recipes with 'results' table (multiple products)
    if v.results then
        for _, results in ipairs(v.results) do
            if results.type == "item" then
                local item = all_items[results.name]
                local module_prot = all_modules[results.name]
                local tool_prot = all_tools[results.name]
                local ammo_prot = all_ammo[results.name]
                if item and flagscheck(item.flags) then
                    results.amount = amoutcheck(results.amount, results.amount_max, results.amount_min, item, v.name)
                elseif module_prot and flagscheck(module_prot.flags) then
                    results.amount = amoutcheck(results.amount, results.amount_max, results.amount_min, module_prot, v.name)
                elseif tool_prot and flagscheck(tool_prot.flags) then
                    results.amount = amoutcheck(results.amount, results.amount_max, results.amount_min, tool_prot, v.name)
                elseif ammo_prot and flagscheck(ammo_prot.flags) then
                    results.amount = amoutcheck(results.amount, results.amount_max, results.amount_min, ammo_prot, v.name)
                end
            elseif results.type == "fluid" then
                local fluid = all_fluids[results.name]
                if fluid then
                    results.amount = amoutcheck(results.amount, results.amount_max, results.amount_min, fluid, v.name)
                end
            end
        end
    end
    ::continue::  -- Continue label for the goto statement
end
