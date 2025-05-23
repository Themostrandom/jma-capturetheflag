local abs = math.abs
local stab_slash_time = 20/60 - 0.2
local stab_slash_cooldown_after = 0.2
local player_anim_data = {}
ctf_player = {
	animation_time = {
		-- Animation Frames / Animation Framerate + Cooldown Time - 0.1
		stab_slash = stab_slash_time + stab_slash_cooldown_after,
	},
}

local angle_tolerance = 2 -- in degrees

player_api.register_model("character.b3d", {
	animation_speed = 30,
	textures = {"character.png"},
	animations = {
		-- Standard animations.
		stand     = {x = 0,   y = 79},
		lay       = {x = 162, y = 166, eye_height = 0.3,
			collisionbox = {-0.6, 0.0, -0.6, 0.6, 0.3, 0.6}},
		walk      = {x = 168, y = 187},
		mine      = {x = 189, y = 198},
		walk_mine = {x = 200, y = 219},
		sit       = {x = 81,  y = 160, eye_height = 0.8,
			collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.0, 0.3}},
		stab      = {x = 221, y = 241, frame_loop = false},
		slash     = {x = 242, y = 262, frame_loop = false},
	},
	collisionbox = {-0.3, 0.01, -0.3, 0.3, 1.71, 0.3},
	stepheight = 0.6,
	eye_height = 1.47,
})

local function is_angle_different(old_angle, new_angle)
	if not old_angle then return true end
	return abs(old_angle - new_angle) > angle_tolerance
end

minetest.register_on_joinplayer(function(player)
	player_api.set_model(player, "character.b3d")
	player:set_local_animation(nil, nil, nil, nil, 0)
	local name = player:get_player_name()
	player_anim_data[name] = {
		timer = 0,
		r_hand_sleep = false,
		last_head_angle = nil,
		last_arm_angle = nil
	}
end)

minetest.register_on_leaveplayer(function(player)
	player_anim_data[player:get_player_name()] = nil
end)

-- Override player_api globalstep

-- Localize for better performance.
local player_set_animation = player_api.set_animation
local get_animation = player_api.get_animation
local player_attached = player_api.player_attached
local models = player_api.registered_models

local stab_slash_timer = {}
minetest.register_globalstep(function(dtime)
	for p, timer in pairs(stab_slash_timer) do
		timer.timeleft = timer.timeleft - dtime

		if timer.timeleft <= 0 then
			if timer.state == "anim" then
				timer.state = "cooldown"
				timer.timeleft = stab_slash_cooldown_after + (timer.extra_time or 0)
			else
				stab_slash_timer[p] = nil
			end
		end
	end
end)

function ctf_player.set_stab_slash_anim(anim_type, player, extra_time)
	stab_slash_timer[player:get_player_name()] = {
		timeleft = stab_slash_time,
		extra_time = extra_time,
		state = "anim"
	}

	player_set_animation(player, anim_type, 60)
end


function player_api.globalstep(dtime)
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local player_data = get_animation(player) or {}
		local model = models[player_data.model]

		if model and not player_attached[name] then
			local controls = player:get_player_control()
			local animation_speed_mod = model.animation_speed or 30

			-- Determine if the player is sneaking, and reduce animation speed if so
			if controls.sneak then
				animation_speed_mod = animation_speed_mod / 2
			end

			-- Apply animations based on what the player is doing
			if player:get_hp() == 0 then
				player_set_animation(player, "lay")
			elseif not stab_slash_timer[name] or stab_slash_timer[name].state == "cooldown" then
				local r_hand = false
				if controls.up or controls.down or controls.left or controls.right then
					if controls.LMB or controls.RMB then
						local wielded = player:get_wielded_item()

						if not wielded or not wielded:get_definition().disable_mine_anim then
							player_set_animation(player, "walk_mine", animation_speed_mod)
							r_hand = true
						else
							player_set_animation(player, "walk", animation_speed_mod)
						end
					else
						player_set_animation(player, "walk", animation_speed_mod)
					end
				elseif controls.LMB or controls.RMB then
					local wielded = player:get_wielded_item()

					if not wielded or not wielded:get_definition().disable_mine_anim then
						player_set_animation(player, "mine", animation_speed_mod)
						r_hand = true
					else
						player_set_animation(player, "stand", animation_speed_mod)
					end
				else
					player_set_animation(player, "stand", animation_speed_mod)
				end

				local anim_data = player_anim_data[name]
				local timer = anim_data.timer
				local v_deg = math.deg(player:get_look_vertical())

				if v_deg > 90 then
					v_deg = 90
				elseif v_deg < -90 then
					v_deg = -90
				end

				if timer > 0.15 then
					if is_angle_different(anim_data.last_head_angle, v_deg) then
						player:set_bone_position("Head", {x = 0, y = 6.1, z = 0}, {x = -v_deg, y = 0, z = 0})
						anim_data.last_head_angle = v_deg
					end
					timer = 0
				end
				timer = timer + dtime
				anim_data.timer = timer

				if r_hand then
					local arm_angle = -v_deg
					if anim_data.r_hand_sleep or is_angle_different(anim_data.last_arm_angle, arm_angle) then
						player:set_bone_position("Arm_Right_Rot", {x = -2.1, y = 5.2, z = 0}, {x = 180, y = arm_angle, z = -90})
						anim_data.last_arm_angle = arm_angle
						anim_data.r_hand_sleep = false
					end
				elseif not anim_data.r_hand_sleep then
					player:set_bone_position("Arm_Right_Rot", {x = -2.1, y = 5.2, z = 0}, {x = 180, y = 0, z = -90})
					anim_data.last_arm_angle = 0
					anim_data.r_hand_sleep = true
				end
			end
		end
	end
end
