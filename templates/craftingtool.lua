local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local modpath_default = minetest.get_modpath("default")

--TODO: currently, this acts as useful inventory storage space in addition to crafting. Would be nice to do something about that, perhaps making the "input" inventory illusory. Will require modification to the "craft_stack" method or perhaps a variant on it.

-- table_def can have the following:
--{
--	show_guides = true or false,
--	alphabetize_items = true or false,
--	description = string,
--	append_to_formspec = string,
--}

simplecrafting_lib.player_contexts = simplecrafting_lib.player_contexts or {}

simplecrafting_lib.generate_tool_functions = function(craft_type, table_def)

if table_def == nil then
	table_def = {}
end

local output_width = 8
local output_height = 6
local output_count = output_width * output_height

local function refresh_output(inv, max_mode)
	local craftable = simplecrafting_lib.get_craftable_items(craft_type, inv:get_list(craft_type.."_input"), max_mode, table_def.alphabetize_items)
	inv:set_size(craft_type.."_output", #craftable + (output_count - (#craftable%output_count)))
	inv:set_list(craft_type.."_output", craftable)
end

local function make_formspec(row, item_count, max_mode)
	if item_count < output_count then
		row = 0
	elseif (row*output_width)+output_count > item_count then
		row = (item_count - output_count) / output_width
	end

	local inventory = {
		"size[10.2,10.2]",
		"list[current_player;"..craft_type.."_input;0,0.5;2,5;]",
		"list[current_player;"..craft_type.."_output;2.2,0;"..output_width..","..output_height..";" , tostring(row*output_width), "]",
		"list[current_player;main;1.1,6.25;8,1;]",
		"list[current_player;main;1.1,7.5;8,3;8]",
		"listring[current_player;"..craft_type.."_output]",
		"listring[current_player;main]",
		"listring[current_player;"..craft_type.."_input]",
		"listring[current_player;main]",
	}
	
	if table_def.description then
		inventory[#inventory+1] = "label[0,0;"..table_def.description.."]"
	end
	
	if modpath_default then
		inventory[#inventory+1] = default.gui_bg
		inventory[#inventory+1] = default.gui_bg_img
		inventory[#inventory+1] = default.gui_slots
	end
	
	local pages = false
	local page_button_y = "7.3"
	if item_count > ((row/output_height)+1) * output_count then
		inventory[#inventory+1] = "button[9.3,"..page_button_y..";1,0.75;next;»]"
		inventory[#inventory+1] = "tooltip[next;"..S("Next page of crafting products").."]"
		page_button_y = "8.0"
		pages = true
	end
	if row >= output_height then
		inventory[#inventory+1] = "button[9.3,"..page_button_y..";1,0.75;prev;«]"
		inventory[#inventory+1] = "tooltip[prev;"..S("Previous page of crafting products").."]"
		pages = true
	end
	if pages then
		inventory[#inventory+1] = "label[9.3,6.5;" .. S("Page @1", tostring(row/output_height+1)) .. "]"
	end
	
	if max_mode then
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;"..S("Max\nOutput").."]"
	else
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;"..S("Min\nOutput").."]"
	end
	
	if table_def.show_guides then
		inventory[#inventory+1] = "button[9.3,9.7;1,0.75;show_guide;"..S("Show\nGuide").."]"
	end
	
	if table_def.append_to_formspec then
		inventory[#inventory+1] = table_def.append_to_formspec
	end

	return table.concat(inventory), row
end

local get_or_create_context = function(player)
	local name = player:get_player_name()
	local context = simplecrafting_lib.player_contexts[name]
	if not context then
		context = {row = 0, formspec = make_formspec(0, 0, true)}
		simplecrafting_lib.player_contexts[name] = context
	end
	return context
end

minetest.register_on_joinplayer(function(player)
	local inv = minetest.get_inventory({type="player", name=player:get_player_name()})
	inv:set_size(craft_type.."_input", 2*5)
	inv:set_size(craft_type.."_output", output_count)
end)

minetest.register_on_leaveplayer(function(player)
	simplecrafting_lib.player_contexts[player:get_player_name()] = nil
end)

local function refresh_inv(inv, player)
	local context = get_or_create_context(player)
	local max_mode = context.max_mode
	refresh_output(inv, max_mode)

	local row = context.row
	local form, row = make_formspec(row, inv:get_size(craft_type.."_output"), max_mode)
	context.row = row
	context.formspec = form
	
	minetest.show_formspec(player:get_player_name(),
		"simplecrafting_lib:tool:"..craft_type,
		context.formspec)
end

minetest.register_allow_player_inventory_action(function(player, action, inventory, inventory_info)
	if action == "move" then
		if inventory_info.to_list == craft_type.."_output" then
			return 0
		end
		if inventory_info.to_list == craft_type.."_input" then
			if inventory_info.from_list == craft_type.."_input" then
				return inventory_info.count
			end
			local stack = inventory:get_stack(inventory_info.from_list, inventory_info.from_index)
			if simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
				return inventory_info.count
			end
		end
		if inventory_info.to_list == "main" then
			return inventory_info.count
		end
	end
end)

minetest.register_on_player_inventory_action(function(player, action, inventory, inventory_info)
	if action == "move" then
		local from_output = inventory_info.from_list == craft_type.."_output"
		local to_input = inventory_info.to_list == craft_type.."_input"
		if from_output and (to_input or inventory_info.to_list == "main") then
			local stack = inventory:get_stack(inventory_info.to_list, inventory_info.to_index)
			stack:set_count(inventory_info.count)
			simplecrafting_lib.craft_stack(craft_type, stack, inventory, craft_type.."_input", inventory, inventory_info.to_list, player)
			if simplecrafting_lib.award_crafting then
				simplecrafting_lib.award_crafting(player, stack)
			end
		end
		if from_output or to_input or inventory_info.from_list == craft_type.."_input" then
			refresh_inv(inventory, player)
		end
	end
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if string.sub(formname, 1, 24) ~= "simplecrafting_lib:tool:" then return false end
	if string.sub(formname, 25) ~= craft_type then return false end
	
	local inv = minetest.get_inventory({type="player", name=player:get_player_name()})
	local context = get_or_create_context(player)
	
	local size = inv:get_size(craft_type.."_output")
	local row = context.row
	local refresh = false
	if fields.next then
		minetest.sound_play("paperflip1", {to_player=player:get_player_name(), gain = 1.0})
		row = row + output_height
	elseif fields.prev  then
		minetest.sound_play("paperflip2", {to_player=player:get_player_name(), gain = 1.0})
		row = row - output_height
	elseif fields.max_mode then
		context.max_mode = not context.max_mode
		refresh = true
	elseif fields.show_guide and table_def.show_guides then
		simplecrafting_lib.show_crafting_guide(craft_type, player,
			function()
				minetest.after(0.1, function()
					minetest.show_formspec(player:get_player_name(), formname, context.formspec)
				end)
			end
		)
	else
		return
	end

	context.row = row
	
	if refresh then
		refresh_inv(inv, player)
	end
end)

return function(player)
	local context = get_or_create_context(player)
	minetest.show_formspec(player:get_player_name(),
		"simplecrafting_lib:"..craft_type,
		context.formspec)
end

end
