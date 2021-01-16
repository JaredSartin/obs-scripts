obs = obslua
vlc_source = ""
scene_name = ""
directories = {}
videos_random = false
videos_per = 1
replaying = false
current_transition_sigh = nil

function script_description()
	return "This script allows commercials to be shown when a scene with playlist source is activated. Choose the scene, source, and directories that contain the commercials. Additionally, set the amount of commercials you want to show from each directory. This allows you to have a directory per sponsor/brand and have variants that can show, or one big directory of commercials that will play. If one directory is chosen, the commercials to play value acts as the max commercials otherwise it is chosen directories * commercials to play that is the max commercial count."
end

function script_properties()
	local props = obs.obs_properties_create()

	local v = obs.obs_properties_add_list(props, "vlc_source", "Commercial laylist source (VLC)", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local vsources = obs.obs_enum_sources()
	if vsources ~= nil then
		for _, source in ipairs(vsources) do
			source_id = obs.obs_source_get_id(source)
			if source_id == "vlc_source" then
				local vname = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(v, vname, vname)
			end
		end
	end
	obs.source_list_release(vsources)

	local s = obs.obs_properties_add_list(props, "scene_name", "Commercial playlist scene", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local scenes = obs.obs_frontend_get_scenes()
	if scenes ~= nil then
		for _, scene in ipairs(scenes) do
			local sname = obs.obs_source_get_name(scene)
			obs.obs_property_list_add_string(s, sname, sname)
		end
	end
	obs.source_list_release(scenes)

	obs.obs_properties_add_editable_list(props, "directories", "Commercial directories", obs.OBS_EDITABLE_LIST_TYPE_FILES, nil, nil)
	obs.obs_properties_add_bool(props, "videos_random", "Play videos in random order")
	obs.obs_properties_add_int(props, "videos_per", "Videos to play per directory", 1, 10000, 1)

	return props
end

function script_update(settings)
	vlc_source = obs.obs_data_get_string(settings, "vlc_source")
	scene_name = obs.obs_data_get_string(settings, "scene_name")
	directories = obs.obs_data_get_array(settings, "directories")
	videos_random = obs.obs_data_get_bool(settings, "videos_random")
	videos_per = obs.obs_data_get_int(settings, "videos_per")

	connect_signals()

	-- obs.script_log(obs.LOG_INFO, "INFO: " .. "Hi - this is test") -- ERROR / WARNING / DEBUG / INFO
end

------------------------------------

function connect_signals()
	-- Sources
	local source = obs.obs_get_source_by_name(vlc_source)
	obs.obs_source_release(source)

	obs.signal_handler_disconnect(obs.obs_source_get_signal_handler(source), "media_ended", media_end)

	if source ~= nil then
		obs.signal_handler_connect(obs.obs_source_get_signal_handler(source), "media_ended", handle_media_end)
	end

	-- Scene transitions
	local ct = obs.obs_frontend_get_current_transition()
	local new_sigh = obs.obs_source_get_signal_handler(ct)
	obs.obs_source_release(ct)

	if current_transition_sigh ~= new_sigh then
		if current_transition_sigh ~= nil then
			obs.signal_handler_disconnect(current_transition_sigh, "transition_start", handle_scene_transition)
		end
		obs.signal_handler_connect(new_sigh, "transition_start", handle_scene_transition)
		current_transition_sigh = new_sigh
	end
end

function handle_scene_transition()
	if get_current_scene_name() == scene_name then
		local source = obs.obs_get_source_by_name(vlc_source)
		if source ~= nil then
			local random_playlist = build_playlist()

			local settings = obs.obs_data_create()
			obs.obs_data_set_bool(settings, "loop", false)
			obs.obs_data_set_array(settings, "playlist", random_playlist)
			obs.obs_data_set_bool(settings, "shuffle", videos_random)
			obs.obs_data_set_string(settings, "playback_behavior", stop_restart)

			obs.obs_source_update(source, settings)
			obs.obs_source_release(source)
			obs.obs_data_array_release(random_playlist)
		end
	else
		clear_playlist()
	end
end

function handle_media_end()
	-- print("Media finished")
end

function build_playlist()
	local playlist = obs.obs_data_array_create()
	local directory_count = obs.obs_data_array_count(directories)
	for i = 1, directory_count do
		local directory_obj = obs.obs_data_array_item(directories, i - 1)
		local directory_name = obs.obs_data_get_string(directory_obj, "value")

		-- Build directory list
		local directory_playlist = {}
		local file_handle = nil
		local directory_handle = obs.os_opendir(directory_name)
		repeat
			file_handle = obs.os_readdir(directory_handle)
			if file_handle and not file_handle.directory then
				directory_playlist[#directory_playlist+1] = directory_name .. "/" .. file_handle.d_name
			end
		until not file_handle
		obs.os_closedir(directory_handle)

		-- Choose files from directory
		shuffle(directory_playlist)

		local index = 1
		repeat
			local item = obs.obs_data_create()
			obs.obs_data_set_string(item, "value", directory_playlist[index])
			obs.obs_data_array_push_back(playlist, item)
			obs.obs_data_release(item)
			index = index + 1
		until index >= videos_per
	end

	return playlist
end

function clear_playlist()
	local source = obs.obs_get_source_by_name(vlc_source)
	if source ~= nil then
		local settings = obs.obs_data_create()
		local playlist = obs.obs_data_array_create()

		obs.obs_data_set_array(settings, "playlist", playlist)
		obs.obs_data_set_bool(settings, "loop", false)
		obs.obs_data_set_bool(settings, "shuffle", false)
		obs.obs_data_set_string(settings, "playback_behavior", stop_restart)
		obs.obs_source_update(source, settings)
		obs.obs_data_array_release(playlist)
		obs.obs_data_release(settings)
		obs.obs_source_release(source)
	end
end

function get_current_scene_name()
    local scene_source = obs.obs_frontend_get_current_scene()
    local name = obs.obs_source_get_name(scene_source)
    obs.obs_source_release(scene_source)
    return name
end

function shuffle(list)
	for i = #list, 1, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end