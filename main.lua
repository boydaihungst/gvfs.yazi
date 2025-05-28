--- @since 25.5.28

local M = {}
local home = os.getenv("HOME") or ""
local PLUGIN_NAME = "gvfs-mtp"

local GVFS_ROOT_MOUNTPOINT = "/run/user/" .. tostring(ya.uid()) .. "/gvfs"

---@enum NOTIFY_MSG
local NOTIFY_MSG = {
	CMD_NOT_FOUND = "%s not found. Make sure it is installed.",
	MOUNT_SUCCESS = "Mounted device %s",
	MOUNT_ERROR = "Error: %s",
	UNMOUNT_ERROR = "Device is busy",
	UNMOUNT_SUCCESS = "Unmounted device %s",
	EJECT_SUCCESS = "Ejected device %s, it can safely be removed",
	LIST_DEVICES_EMPTY = "No devices found.",
	DEVICE_IS_DISCONNECTED = "Device is disconnected",
	CANT_ACCESS_PREV_CWD = "Device is disconnected or Previous directory is removed",
}

---@enum DEVICE_CONNECT_STATUS
local DEVICE_CONNECT_STATUS = {
	MOUNTED = 1,
	NOT_MOUNTED = 2,
}

---@enum DEVICE_TYPE
local DEVICE_TYPE = {
	VOLUME = 1,
	MOUNT = 10,
}

---@enum SCHEMA
local SCHEMA = {
	MTP = "mtp",
	SMB = "smb",
	SFTP = "sftp",
	NFS = "nfs",
	GPHOTO2 = "gphoto2",
	FTP = "ftp",
	GOOGLE_DRIVE = "google-drive",
	DNS_SD = "dns-sd",
	DAV = "dav",
	AFP = "afp",
	AFC = "afc",
}
---@enum STATE_KEY
local STATE_KEY = {
	PREV_CWD = "PREV_CWD",
	WHICH_KEYS = "WHICH_KEYS",
	CMD_NOT_FOUND = "CMD_NOT_FOUND",
	ROOT_MOUNTPOINT = "ROOT_MOUNTPOINT",
}

---@enum ACTION
local ACTION = {
	SELECT_THEN_MOUNT = "select-then-mount",
	JUMP_TO_DEVICE = "jump-to-device",
	JUMP_BACK_PREV_CWD = "jump-back-prev-cwd",
	SELECT_THEN_UNMOUNT = "select-then-unmount",
	REMOUNT_KEEP_CWD_UNCHANGED = "remount-current-cwd-device",
}

---@class (exact) Device
---@field name string
---@field mounts Mount[]
---@field type DEVICE_TYPE
---@field schema SCHEMA
---@field bus integer?
---@field device integer?
---@field activation_root string
---@field uri string
---@field can_unmount "1"|"0"
---@field can_eject "1"|"0"
---@field should_automount "1"|"0"

---@class (exact) Mount
---@field name string
---@field uri string
---@field type DEVICE_TYPE
---@field schema SCHEMA
---@field bus integer?
---@field device integer?
---@field default_location string
---@field can_unmount "1"|"0"
---@field can_eject "1"|"0"
---@field is_shadowed "1"|"0"

local function error(s, ...)
	ya.notify({ title = PLUGIN_NAME, content = string.format(s, ...), timeout = 5, level = "error" })
end

local function info(s, ...)
	ya.notify({ title = PLUGIN_NAME, content = string.format(s, ...), timeout = 5, level = "info" })
end

local set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

local get_state = ya.sync(function(state, key)
	return state[key]
end)

local function pathJoin(...)
	-- Detect OS path separator ('\' for Windows, '/' for Unix)
	local separator = package.config:sub(1, 1)
	local parts = { ... }
	local filteredParts = {}
	-- Remove empty strings or nil values
	for _, part in ipairs(parts) do
		if part and part ~= "" then
			table.insert(filteredParts, part)
		end
	end
	-- Join the remaining parts with the separator
	local path = table.concat(filteredParts, separator)
	-- Normalize any double separators (e.g., "folder//file" → "folder/file")
	path = path:gsub(separator .. "+", separator)

	return path
end

local current_dir = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

---run any command
---@param cmd string
---@param args string[]
---@param _stdin? Stdio|nil
---@return Error|nil, Output|nil
local function run_command(cmd, args, _stdin)
	local stdin = _stdin or Command.INHERIT
	local child, cmd_err = Command(cmd):arg(args):stdin(stdin):stdout(Command.PIPED):stderr(Command.PIPED):spawn()

	if not child then
		error("Failed to start `%s` with error: `%s`", cmd, cmd_err)
		return cmd_err, nil
	end

	local output, out_err = child:wait_with_output()
	if not output then
		error("Cannot read `%s` output, error: `%s`", cmd, out_err)
		return out_err, nil
	else
		return nil, output
	end
end

local is_dir = function(dir_path)
	local cha, err = fs.cha(Url(dir_path))
	return not err and cha and cha.is_dir
end

---split string by char
---@param s string
---@return string[]
local function string_to_array(s)
	local array = {}
	for i = 1, #s do
		table.insert(array, s:sub(i, i))
	end
	return array
end

local function is_literal_string(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

local function tbl_deep_clone(original)
	if type(original) ~= "table" then
		return original
	end

	local copy = {}
	for key, value in pairs(original) do
		copy[tbl_deep_clone(key)] = tbl_deep_clone(value)
	end

	return copy
end

local function extract_domain_and_user(s)
	local user = ""
	local domain = ""

	-- Attempt 1: Look for user@domain first (if it exists)
	local temp_user, temp_domain_part = s:match("^([^@,/]+)@([^,/]+)")
	if temp_user and temp_domain_part then
		-- If user@domain found, the domain might be followed by a comma
		-- We want the part before the first comma or slash in the domain part
		domain = temp_domain_part:match("^[^,/]+") or temp_domain_part
		user = temp_user
	else
		-- Attempt 2: No user@domain, so try to get domain from the start (before first comma or slash)
		domain = s:match("^([^,/]+)")
		if not domain then
			domain = "" -- Ensure domain is not nil if no pattern matches
		end
	end

	-- Now, regardless of how the domain was found, look for 'user='
	-- Match 'user=' followed by one or more characters that are not a comma
	-- This handles 'user=value,' or 'user=value' at the end of the string
	local user_match = s:match("user=([^,]+)")
	if user_match then
		user = user_match -- Overwrite or set the user found later
	end

	return domain, user
end

local function is_mountpoint_belong_to_volume(mount, volume)
	return mount.is_shadowed ~= "1"
		and mount.schema == volume.schema
		and (mount.uri == volume.uri or (mount.bus == volume.bus and mount.device == volume.device))
end

local function parse_devices(raw_input)
	local volumes = {}
	local mounts = {}
	local current_volume = nil
	local current_mount = nil

	for line in raw_input:gmatch("[^\r\n]+") do
		local clean_line = line:match("^%s*(.-)%s*$")

		-- Match volume(0)
		local volume_name = clean_line:match("^Volume%(%d+%):%s*(.+)$")
		if volume_name then
			current_mount = nil
			current_volume = { name = volume_name, mounts = {}, type = DEVICE_TYPE.VOLUME }
			table.insert(volumes, current_volume)

		-- Match mount(0)
		elseif clean_line:match("^Mount%(%d+%):") then
			current_volume = nil
			local mount_name, mount_uri = clean_line:match("^Mount%(%d+%):%s*(.-)%s*->%s*(.+)$")
			if not mount_name then
				mount_name = clean_line:match("^Mount%(%d+%):%s*(.+)$")
			end

			current_mount = { name = mount_name or "", uri = mount_uri or "", type = DEVICE_TYPE.MOUNT }

			for _, value in pairs(SCHEMA) do
				if mount_uri:match("^" .. value) then
					current_mount.schema = value
				end
			end

			-- Case mtp/gphoto2 usb bus dev
			if mount_uri then
				local protocol, bus, device = mount_uri:match("^(%w+)://%[usb:(%d+),(%d+)%]/")
				-- Attach to mount or volume
				if protocol and (protocol == SCHEMA.MTP or protocol == SCHEMA.GPHOTO2) and bus and device then
					current_mount.bus = bus
					current_mount.device = device
				end
			end
			table.insert(mounts, current_mount)

		-- Match key=value metadata
		else
			local key, value = clean_line:match("^(%S+)%s*=%s*(.+)$")
			if key and value then
				-- Attach to mount or volume
				local target = current_mount or current_volume
				if target then
					target[key] = value
				end
			else
				local bus, device = line:match(".*:%s*'/dev/bus/usb/(%d+)/(%d+)'")
				-- Attach to mount or volume
				if bus and device then
					local target = current_mount or current_volume
					if target then
						target.bus = bus
						target.device = device
					end
				end
			end
		end
	end

	-- Remove shadowed mounts and attach mount points to volumes
	for i = #volumes, 1, -1 do
		local v = volumes[i]
		if v.activation_root then
			v.uri = v.activation_root
		end
		-- Attach schema to volume
		for _, value in pairs(SCHEMA) do
			if v.uri:match("^" .. value) then
				v.schema = value
			end
		end

		-- Attach mount points to volume
		for j = #mounts, 1, -1 do
			if is_mountpoint_belong_to_volume(mounts[j], v) then
				table.insert(v.mounts, mounts[j])
				table.remove(mounts, j)
			end
		end
	end

	for _, m in ipairs(mounts) do
		if m.is_shadowed ~= "1" then
			m.mounts = { tbl_deep_clone(m) }
			table.insert(volumes, m)
		end
	end
	return volumes
end

---@param target Device|Mount
---@return string
local function get_mount_path(target)
	if not target then
		return ""
	end
	local root_mountpoint = get_state(STATE_KEY.ROOT_MOUNTPOINT)
	if
		target.schema == SCHEMA.DAV
		or target.schema == SCHEMA.AFP
		or target.schema == SCHEMA.GOOGLE_DRIVE
		or target.schema == SCHEMA.NFS
		or target.schema == SCHEMA.SFTP
		or target.schema == SCHEMA.SMB
		or target.schema == SCHEMA.DNS_SD
	then
		local schema, uri = string.match(target.uri, "([^:]+)://([^/]+)")
		if not uri or not schema then
			return ""
		end

		local domain, user = extract_domain_and_user(uri)
		uri = is_literal_string(target.schema .. ":host=" .. (user and (user .. "@") or "") .. domain)
		local uri2 = is_literal_string(target.schema .. ":host=" .. domain)
		local files, _ = fs.read_dir(Url(root_mountpoint), {})
		for _, file in ipairs(files or {}) do
			if file.name:match("^" .. uri .. ".*") or file.name:match("^" .. uri2 .. ".*") then
				return tostring(file.url)
			end
		end
		return ""
	else
		local uri = target.uri:gsub("//", "host=", 1)
		return pathJoin(root_mountpoint, uri)
	end
end

---@param device Device
local function is_mounted(device)
	return device and (#device.mounts > 0 or fs.cha(Url(get_mount_path(device))))
end

---mount mtp device
---@param opts {device: Device, max_retry?: integer, retries?: integer}
---@return boolean
local function mount_device(opts)
	local device = opts.device
	local max_retry = opts.max_retry or 3
	local retries = opts.retries or 0

	-- prevent re-mount
	if is_mounted(opts.device) then
		return true
	end

	local err, res = run_command("gio", { "mount", device.uri })

	local mount_success = res and res.status and res.status.success

	if mount_success then
		info(NOTIFY_MSG.MOUNT_SUCCESS, device.name)
		return true
	end

	-- show notification after get max retry
	if retries >= max_retry then
		error(NOTIFY_MSG.MOUNT_ERROR, tostring(err) or "Unknown")
		return false
	end

	-- Increase retries every run
	retries = retries + 1
	return mount_device({
		device = device,
		retries = retries,
		max_retry = max_retry,
	})
end

--- Return list of connected devices
---@return Device[]
local function list_gvfs_device()
	---@type Device[]
	local devices = {}
	local _, res = run_command("gio", { "mount", "-li" })
	if res then
		if res.status.success then
			devices = parse_devices(res.stdout)
		end
	end
	return devices
end

---Return list of mounted devices
---@param status DEVICE_CONNECT_STATUS
---@return Device[]
local function list_gvfs_device_by_status(status)
	local devices = list_gvfs_device()
	local devices_filtered = {}
	for _, d in ipairs(devices) do
		local mounted = is_mounted(d)
		if status == DEVICE_CONNECT_STATUS.MOUNTED and mounted then
			table.insert(devices_filtered, d)
		end
		if status == DEVICE_CONNECT_STATUS.NOT_MOUNTED and not mounted then
			table.insert(devices_filtered, d)
		end
	end
	return devices_filtered
end

--- Unmount a mtp device
---@param device Device
---@param eject boolean? eject = true if user want to safty unplug the device
---@return boolean
local function unmount_gvfs(device, eject)
	if not device then
		return true
	end
	local unmount_method = "-u"
	if eject then
		unmount_method = "-e"
	end
	for _, mount in ipairs(device.mounts) do
		local cmd_err, res = run_command("gio", { "mount", unmount_method, mount.uri })
		if cmd_err or (res and not res.status.success) then
			if res and res.stderr:find("mount doesn.*t implement .*eject.* or .*eject_with_operation.*") then
				return unmount_gvfs(device, false)
			end
			error(NOTIFY_MSG.UNMOUNT_ERROR)
			return false
		end
		if not cmd_err and res and res.status.success then
			if eject then
				info(NOTIFY_MSG.EJECT_SUCCESS, mount.name)
			else
				info(NOTIFY_MSG.UNMOUNT_SUCCESS, mount.name)
			end
		end
		return true
	end
end

---show which key to select device from list
---@param devices Device[]
local function select_device_which_key(devices)
	local which_keys = get_state(STATE_KEY.WHICH_KEYS)
		or "1234567890qwertyuiopasdfghjklzxcvbnm-=[]\\;',./!@#$%^&*()_+{}|:\"<>?"
	local allow_key_array = string_to_array(which_keys)
	local cands = {}

	for idx, d in ipairs(devices) do
		if idx > #allow_key_array then
			break
		end
		table.insert(
			cands,
			{ on = tostring(allow_key_array[idx]), desc = (d.name or "NO_NAME") .. " (" .. d.schema .. ")" }
		)
	end

	if #cands == 0 then
		return
	end
	local selected_idx = ya.which({
		cands = cands,
	})

	if selected_idx and selected_idx > 0 then
		return devices[selected_idx]
	end
end

---@param path string
---@param devices Device[]
---@return Device?
local function get_device_from_path(path, devices)
	local root_mountpoint = get_state(STATE_KEY.ROOT_MOUNTPOINT)
	local schema, uri = string.match(path, root_mountpoint .. "/([^:]+):host=([^/]+)")
	local domain, user = nil, nil
	if not uri or not schema then
		return nil
	end
	if
		schema == SCHEMA.DAV
		or schema == SCHEMA.AFP
		or schema == SCHEMA.GOOGLE_DRIVE
		or schema == SCHEMA.NFS
		or schema == SCHEMA.SFTP
		or schema == SCHEMA.SMB
		or schema == SCHEMA.DNS_SD
	then
		domain, user = extract_domain_and_user(uri)
	else
		uri = is_literal_string(schema .. "://" .. uri)
	end
	if not devices then
		devices = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.MOUNTED)
	end
	for _, device in ipairs(devices) do
		if device.uri:match("^" .. uri .. ".*") then
			return device
		end
		for _, mount in ipairs(device.mounts) do
			if mount.uri:match("^" .. uri .. ".*") then
				return device
			else
				local _, d_uri = string.match(mount.uri, "^([^:]+)://([^/]+)")
				local d_domain, d_user = extract_domain_and_user(d_uri)
				if d_domain == domain and d_user == user then
					return device
				end
			end
		end
	end
	return nil
end

--- Jump to device mountpoint
---@param device Device?
local function jump_to_device_mountpoint_action(device)
	if not device then
		local list_devices = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.MOUNTED)
		device = #list_devices == 1 and list_devices[1] or select_device_which_key(list_devices)
	end
	if not device then
		return
	end
	local success = is_mounted(device)

	if success then
		local mnt_point = get_mount_path(device)
		set_state(STATE_KEY.PREV_CWD, current_dir())
		ya.emit("cd", { mnt_point })
	else
		error(NOTIFY_MSG.DEVICE_IS_DISCONNECTED)
	end
end

--- Jump to previous directory
local function jump_to_prev_cwd_action()
	local prev_cwd = get_state(STATE_KEY.PREV_CWD)
	if not prev_cwd then
		return
	end
	if is_dir(prev_cwd) then
		set_state(STATE_KEY.PREV_CWD, current_dir())
		ya.emit("cd", { prev_cwd })
	else
		error(NOTIFY_MSG.CANT_ACCESS_PREV_CWD)
	end
end

--- mount action
---@param opts { jump: boolean?, device: Device? }?
local function mount_action(opts)
	local selected_device
	-- Let user select a device if device is not specified
	if not opts or not opts.device then
		local list_devices = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.NOT_MOUNTED)
		-- NOTE: Automatically select the first device if there is only one device
		selected_device = #list_devices == 1 and list_devices[1] or select_device_which_key(list_devices)
		if #list_devices == 0 then
			-- If every devices are mounted, then select the first one
			local list_devices_mounted = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.MOUNTED)
			selected_device = #list_devices_mounted >= 1 and list_devices_mounted[1] or nil
			if not selected_device then
				error(NOTIFY_MSG.LIST_DEVICES_EMPTY)
			end
		end
	else
		selected_device = opts.device
	end
	if not selected_device then
		return
	end

	local success = mount_device({
		device = selected_device,
	})

	if success and opts and opts.jump then
		jump_to_device_mountpoint_action(selected_device)
	end
	return success
end

local save_tab_hovered = ya.sync(function()
	local hovered_item_per_tab = {}
	for _, tab in ipairs(cx.tabs) do
		table.insert(hovered_item_per_tab, {
			id = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
			cwd = tostring(tab.current.cwd),
		})
	end
	return hovered_item_per_tab
end)

local redirect_unmounted_tab_to_home = ya.sync(function(_, unmounted_url)
	if not unmounted_url or unmounted_url == "" then
		return
	end
	for _, tab in ipairs(cx.tabs) do
		if tab.current.cwd:starts_with(unmounted_url) then
			ya.emit("cd", {
				home,
				tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
			})
		end
	end
end)

--- unmount action
--- @param device Device?
--- @param eject boolean? eject = true if user want to safty unplug the device
local function unmount_action(device, eject)
	local selected_device
	if not device then
		local list_devices = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.MOUNTED)
		-- NOTE: Automatically select the first device if there is only one device
		selected_device = #list_devices == 1 and list_devices[1] or select_device_which_key(list_devices)
		if not selected_device and #list_devices == 0 then
			error(NOTIFY_MSG.LIST_DEVICES_EMPTY)
		end
	end
	if device then
		selected_device = device
	end
	if not selected_device then
		return
	end

	local mount_path = get_mount_path(selected_device)
	local success = unmount_gvfs(selected_device, eject)
	if success then
		redirect_unmounted_tab_to_home(mount_path)
		-- cd to home for all tabs within the device, and then restore the tabs location
	end
end

local function remount_keep_cwd_unchanged_action()
	local devices = list_gvfs_device()
	local current_tab_device = get_device_from_path(current_dir(), devices)
	if not current_tab_device then
		return
	end
	local root_mountpoint = get_state(STATE_KEY.ROOT_MOUNTPOINT)
	local tabs = save_tab_hovered()
	local saved_matched_tabs = {}
	-- cd to home for all tabs within the device, and then restore the tabs location
	for _, tab in ipairs(tabs) do
		local tab_device = get_device_from_path(tostring(tab.cwd), devices)
		if tab_device and tab_device.name == current_tab_device.name and tab_device.type == current_tab_device.type then
			table.insert(saved_matched_tabs, tab)
			ya.emit("cd", {
				root_mountpoint,
				tab = tab.id,
			})
		end
	end
	mount_action({ jump = false, device = current_tab_device })
	for _, tab in ipairs(saved_matched_tabs) do
		ya.emit("cd", {
			tostring(tab.cwd),
			tab = tab.id,
		})
	end
end

local function check_cmd_exist(cmd)
	local cmd_not_found = get_state(STATE_KEY.CMD_NOT_FOUND)
	if cmd_not_found == nil then
		local cmd_err, _ = run_command(cmd, {})
		cmd_not_found = cmd_err ~= nil
	end
	if cmd_not_found then
		error(NOTIFY_MSG.CMD_NOT_FOUND, cmd)
	end
	set_state(STATE_KEY.CMD_NOT_FOUND, cmd_not_found)
	return cmd_not_found
end

---setup function in yazi/init.lua
---@param opts {}
function M:setup(opts)
	if opts and opts.which_keys and type(opts.which_keys) == "string" then
		set_state(STATE_KEY.WHICH_KEYS, opts.which_keys)
	end
	if opts and opts.root_mountpoint and type(opts.root_mountpoint) == "string" then
		set_state(STATE_KEY.ROOT_MOUNTPOINT, opts.root_mountpoint)
	else
		set_state(STATE_KEY.ROOT_MOUNTPOINT, GVFS_ROOT_MOUNTPOINT)
	end
end

---@param job {args: string[], args: {jump: boolean?, eject: boolean?}}
function M:entry(job)
	check_cmd_exist("gio")
	local action = job.args[1]
	local jump = job.args.jump or false
	local eject = job.args.eject or false
	-- Select a device then mount
	if action == ACTION.SELECT_THEN_MOUNT then
		mount_action({ jump = jump })
		-- select a device then unmount
	elseif action == ACTION.SELECT_THEN_UNMOUNT then
		unmount_action(nil, eject)
		-- remount device within current cwd
	elseif action == ACTION.REMOUNT_KEEP_CWD_UNCHANGED then
		remount_keep_cwd_unchanged_action()
		-- select a device then go to its mounted point
	elseif action == ACTION.JUMP_TO_DEVICE then
		jump_to_device_mountpoint_action()
	elseif action == ACTION.JUMP_BACK_PREV_CWD then
		jump_to_prev_cwd_action()
	end
	ya.render()
end

return M
