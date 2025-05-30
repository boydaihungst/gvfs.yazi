--- @since 25.5.28

local M = {}
local shell = os.getenv("SHELL") or ""
local home = os.getenv("HOME") or ""
local PLUGIN_NAME = "gvfs"

local USER_ID = ya.uid()
local USER_NAME = tostring(ya.user_name(USER_ID))
local GVFS_ROOT_MOUNTPOINT = "/run/user/" .. tostring(USER_ID) .. "/gvfs"
local GVFS_ROOT_MOUNTPOINT_FILE = "/run/media/" .. USER_NAME

---@enum NOTIFY_MSG
local NOTIFY_MSG = {
	CANT_CREATE_SAVE_FOLDER = "Can't create save folder: %s",
	CANT_SAVE_DEVICES = "Can't write to save file: %s",
	CMD_NOT_FOUND = "%s not found. Make sure it is installed.",
	MOUNT_SUCCESS = "Mounted device %s",
	MOUNT_ERROR = "Mount error: %s",
	UNMOUNT_ERROR = "Unmount error: %s",
	UNMOUNT_SUCCESS = "Unmounted device %s",
	EJECT_SUCCESS = "Ejected device %s, it can safely be removed",
	LIST_DEVICES_EMPTY = "No devices found.",
	DEVICE_IS_DISCONNECTED = "Device is disconnected",
	CANT_ACCESS_PREV_CWD = "Device is disconnected or Previous directory is removed",
	URI_CANT_BE_EMPTY = "URI can't be empty",
	URI_IS_INVALID = "URI is invalid",
	UNSUPPORTED_SCHEME = "Unsupported scheme %s",
	DISPLAY_NAME_CANT_BE_EMPTY = "Display name can't be empty",
	MOUNT_ERROR_PASSWORD = "Failed to mount device %s, please check your password",
	MOUNT_ERROR_USERNAME = "Failed to mount device %s, please check your username",
	LIST_MOUNTS_EMPTY = "List mounts is empty",
}

---@enum DEVICE_CONNECT_STATUS
local DEVICE_CONNECT_STATUS = {
	MOUNTED = 1,
	NOT_MOUNTED = 2,
}

---@enum SCHEME
local SCHEME = {
	MTP = "mtp",
	SMB = "smb",
	SFTP = "sftp",
	NFS = "nfs",
	GPHOTO2 = "gphoto2",
	FTP = "ftp",
	FTPS = "ftps",
	FTPIS = "ftpis",
	GOOGLE_DRIVE = "google-drive",
	DNS_SD = "dns-sd",
	DAV = "dav",
	DAVS = "davs",
	DAVSD = "dav+sd",
	DAVSSD = "davs+sd",
	AFP = "afp",
	AFC = "afc",
	FILE = "file",
}
---@enum STATE_KEY
local STATE_KEY = {
	PREV_CWD = "PREV_CWD",
	WHICH_KEYS = "WHICH_KEYS",
	CMD_NOT_FOUND = "CMD_NOT_FOUND",
	ROOT_MOUNTPOINT = "ROOT_MOUNTPOINT",
	SAVE_PATH = "SAVE_PATH",
	MOUNTS = "MOUNTS",
}

---@enum ACTION
local ACTION = {
	SELECT_THEN_MOUNT = "select-then-mount",
	JUMP_TO_DEVICE = "jump-to-device",
	JUMP_BACK_PREV_CWD = "jump-back-prev-cwd",
	SELECT_THEN_UNMOUNT = "select-then-unmount",
	REMOUNT_KEEP_CWD_UNCHANGED = "remount-current-cwd-device",
	ADD_MOUNT = "add-mount",
	EDIT_MOUNT = "edit-mount",
	REMOVE_MOUNT = "remove-mount",
}

---@class (exact) Device
---@field name string
---@field mounts Mount[]
---@field scheme SCHEME
---@field bus integer?
---@field device integer?
---@field uuid string?
---@field owner string?
---@field activation_root string?
---@field uri string
---@field is_manually_added boolean?
---@field can_unmount "1"|"0"
---@field can_eject "1"|"0"
---@field should_automount "1"|"0"
---@field password string?

---@class (exact) Mount
---@field name string
---@field uri string
---@field scheme SCHEME
---@field bus integer?
---@field device integer?
---@field uuid string?
---@field owner string?
---@field default_location string?
---@field can_unmount "1"|"0"|nil
---@field can_eject "1"|"0"|nil
---@field is_shadowed "1"|"0"|nil
---@field password string?

---@param is_password boolean?
local function show_input(title, is_password, value)
	local input_value, input_pw_event = ya.input({
		title = title,
		value = value or "",
		obscure = is_password or false,
		position = { "top-center", y = 3, w = 60 },
	})
	if input_pw_event ~= 1 then
		return nil, nil
	end
	return input_value, input_pw_event
end

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

---@enum PUBSUB_KIND
local PUBSUB_KIND = {
	mounts_changed = "@" .. PLUGIN_NAME .. "-" .. "mounts-changed",
}

--- broadcast through pub sub to other instances
---@param _ table state
---@param pubsub_kind PUBSUB_KIND
---@param data any
---@param to number default = 0 to all instances
local broadcast = ya.sync(function(_, pubsub_kind, data, to)
	ps.pub_to(to or 0, pubsub_kind, data)
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

local function path_quote(path)
	if not path or path == "" then
		return path
	end
	local result = "'" .. string.gsub(tostring(path), "'", "'\\''") .. "'"
	return result
end

local function extract_domain_user_from_uri(s)
	local user = ""
	local domain = ""
	local port = ""

	-- Attempt 1: Look for user@domain:port first (if it exists)
	-- davs://user@domain/dav
	local scheme, temp_user, temp_domain_part = s:match("^([^:]+)://([^@/]+)@([^/]+)")
	if temp_user and temp_domain_part then
		-- If user@domain found, the domain might be followed by a comma
		-- We want the part before the first comma or slash in the domain part
		user = temp_user
		-- domain:port
		domain, port = temp_domain_part:match("^([^:/]+):([^:/]+)")
		if not port or port == "" then
			port = ""
			domain = temp_domain_part:match("^[^/]+") or temp_domain_part
		end
	else
		-- Attempt 2: No user@domain, so try to get domain from the start (before first comma or slash)
		-- davs://domain/dav
		scheme, temp_domain_part = s:match("^([^:]+)://([^/]+)")
		if temp_domain_part then
			domain, port = temp_domain_part:match("^([^:/]+):([^:/]+)")
			if not port or port == "" then
				port = ""
				domain = temp_domain_part:match("^[^/]+") or temp_domain_part
			end
		end
	end

	local ssl = (s:match("^davs") or s:match("^ftps") or s:match("^ftpis") or s:match("^https")) and true or false
	local prefix = s:match(".*" .. domain .. (port ~= "" and ":" .. port or "") .. "/(.+)$") or ""
	return scheme, domain, user, ssl, prefix, port
end

local function uri_decode(str)
	if not str then
		return nil
	end
	str = string.gsub(str, "+", " ")
	str = string.gsub(str, "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end)
	return str
end

local function extract_domain_user_from_foldername(s)
	local user = ""
	local domain = ""
	local ssl = false
	local prefix = ""
	local scheme
	local port
	scheme, s = s:match("^([^:]+):(.+)")

	for part in s:gmatch("([^,]+)") do
		if part:match("^host=(.+)") then
			domain = part:match("^host=([^,/]+)")
		end
	end
	domain = uri_decode(s:match("^host=([^,]+)")) or ""
	user = uri_decode(s:match(".*user=([^,]+)")) or ""
	ssl = s:match(".*ssl=true") and true or false
	prefix = uri_decode(s:match(".*prefix=([^,]+)")) or ""
	port = s:match(".*port=([^,]+)") or ""
	if prefix then
		prefix = prefix:match("/(.+)") or ""
	end
	return scheme, domain, user, ssl, prefix, port
end

local function is_mountpoint_belong_to_volume(mount, volume)
	return mount.is_shadowed ~= "1"
		and mount.scheme == volume.scheme
		and (
			mount.uri == volume.uri
			or mount.uuid == volume.uuid
			or (mount.bus == volume.bus and mount.device == volume.device)
		)
end

local function parse_devices(raw_input)
	local volumes = {}
	local mounts = {}
	local predefined_mounts = tbl_deep_clone(get_state(STATE_KEY.MOUNTS)) or {}
	local current_volume = nil
	local current_mount = nil

	for line in raw_input:gmatch("[^\r\n]+") do
		local clean_line = line:match("^%s*(.-)%s*$")

		-- Match volume(0)
		local volume_name = clean_line:match("^Volume%(%d+%):%s*(.+)$")
		if volume_name then
			current_mount = nil
			current_volume = { name = volume_name, mounts = {} }
			table.insert(volumes, current_volume)

		-- Match mount(0)
		elseif clean_line:match("^Mount%(%d+%):") then
			current_volume = nil
			current_mount = nil
			local mount_name, mount_uri = clean_line:match("^Mount%(%d+%):%s*(.-)%s*->%s*(.+)$")
			if not mount_name then
				mount_name = clean_line:match("^Mount%(%d+%):%s*(.+)$")
			end

			current_mount = { name = mount_name or "", uri = mount_uri or "" }

			local m_scheme, m_domain, m_user, m_ssl, m_prefix, m_port = extract_domain_user_from_uri(mount_uri)
			for m = #predefined_mounts, 1, -1 do
				local scheme, domain, user, ssl, prefix, port = extract_domain_user_from_uri(predefined_mounts[m].uri)
				if
					m_scheme == scheme
					and m_domain == domain
					and m_user == user
					and m_ssl == ssl
					and m_prefix == prefix
					and m_port == port
				then
					current_mount = table.remove(predefined_mounts, m)
				end
			end

			for _, value in pairs(SCHEME) do
				if mount_uri:match("^" .. value .. ":") then
					current_mount.scheme = value
				end
			end

			-- Case mtp/gphoto2 usb bus dev
			if mount_uri then
				local protocol, bus, device = mount_uri:match("^(%w+)://%[usb:(%d+),(%d+)%]/")
				-- Attach to mount or volume
				if protocol and (protocol == SCHEME.MTP or protocol == SCHEME.GPHOTO2) and bus and device then
					current_mount.bus = bus
					current_mount.device = device
				end
				-- file:///run/media/huyhoang/6412-E4B2
				local owner, uuid = mount_uri:match("^file:///run/media/(.+)/(.+)")
				if owner and uuid then
					current_mount.owner = owner
					current_mount.uuid = uuid
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

		-- Attach scheme to volume
		if v.uuid then
			v.scheme = SCHEME.FILE
		else
			for _, value in pairs(SCHEME) do
				if v.uri and v.uri:match("^" .. value .. ":") then
					v.scheme = value
				end
			end
		end

		-- Attach mount points to volume
		for j = #mounts, 1, -1 do
			if is_mountpoint_belong_to_volume(mounts[j], v) then
				table.insert(v.mounts, table.remove(mounts, j))
			end
		end
	end

	for _, m in ipairs(predefined_mounts) do
		m.mounts = { tbl_deep_clone(m) }
		table.insert(volumes, m)
	end

	for _, m in ipairs(mounts) do
		if m.is_shadowed ~= "1" and m.uri then
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
		target.scheme == SCHEME.DAV
		or target.scheme == SCHEME.AFP
		or target.scheme == SCHEME.DAVS
		or target.scheme == SCHEME.DAVSD
		or target.scheme == SCHEME.DAVSSD
		or target.scheme == SCHEME.FTP
		or target.scheme == SCHEME.FTPS
		or target.scheme == SCHEME.FTPIS
		or target.scheme == SCHEME.GOOGLE_DRIVE
		or target.scheme == SCHEME.NFS
		or target.scheme == SCHEME.SFTP
		or target.scheme == SCHEME.SMB
		or target.scheme == SCHEME.DNS_SD
	then
		local scheme, domain, user, ssl, prefix, port = extract_domain_user_from_uri(target.uri)
		local files, _ = fs.read_dir(Url(root_mountpoint), {})
		for _, file in ipairs(files or {}) do
			local f_scheme, f_domain, f_user, f_ssl, f_prefix, f_port = extract_domain_user_from_foldername(file.name)
			if
				scheme:match("^" .. f_scheme)
				and f_domain == domain
				and f_user == user
				and f_ssl == ssl
				and f_prefix == prefix
				and f_port == port
			then
				return tostring(file.url)
			end
		end
		return ""
	elseif target.scheme == SCHEME.FILE and target.uuid then
		return pathJoin(GVFS_ROOT_MOUNTPOINT_FILE, target.uuid)
	elseif target.uri then
		local uri = target.uri:gsub("//", "host=", 1)
		return pathJoin(root_mountpoint, uri)
	end
	return ""
end

---@param device Device
local function is_mounted(device)
	if device and #device.mounts > 0 then
		for _, mount in ipairs(device.mounts) do
			if mount.can_unmount == "1" or mount.can_eject == "1" then
				return true
			end
		end
	end
	local mountpath = get_mount_path(device)
	return mountpath and mountpath ~= "" and fs.cha(Url(mountpath))
end

---mount mtp device
---@param opts {device: Device,username?:string, password?: string, max_retry?: integer, retries?: integer}
---@return boolean
local function mount_device(opts)
	local device = opts.device
	local max_retry = opts.max_retry or 3
	local retries = opts.retries or 0
	local password = opts.password
	local username = opts.username

	-- prevent re-mount
	if is_mounted(opts.device) then
		return true
	end

	local auths = ""
	local auth_string_format = ""
	if password or username then
		if username then
			auths = path_quote(username)
			auth_string_format = auth_string_format .. "%s\n"
		end
		if password then
			auths = auths .. " " .. path_quote(password)
			auth_string_format = auth_string_format .. "%s\n"
		end
	end

	local res, err = Command(shell)
		:arg({
			"-c",
			(auth_string_format ~= "" and "printf " .. path_quote(auth_string_format) .. " " .. auths .. " | " or "")
				.. " gio mount "
				.. (device.uuid and ("-d " .. device.uuid) or path_quote(device.uri)),
		})
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()

	local mount_success = res and res.status and res.status.success

	if mount_success then
		info(NOTIFY_MSG.MOUNT_SUCCESS, device.name)
		return true
	elseif res and res.status.code == 2 then
		if res.stdout:find("Authentication Required") then
			local stdout = res.stdout:match(".*Authentication Required(.*)") or ""
			if stdout:find("\nUser: \n") then
				err = string.format(
					NOTIFY_MSG.MOUNT_ERROR_USERNAME,
					(device.name or "NO_NAME") .. " (" .. device.scheme .. ")"
				)
				if retries < max_retry then
					username, _ = show_input("Enter username:", false)
					if username == nil then
						return false
					end
				end
			end
			if stdout:find("\nPassword: \n") or stdout:find("\nUser: \n") or stdout:find("\nUser %[.*%]: \n") then
				err = string.format(
					NOTIFY_MSG.MOUNT_ERROR_PASSWORD,
					(device.name or "NO_NAME") .. " (" .. device.scheme .. ")"
				)
				if retries < max_retry then
					password, _ = show_input("Enter password:", true)
					if password == nil then
						return false
					end
				end
			end
		end
	end
	-- show notification after get max retry
	if retries >= max_retry then
		err = tostring(err) or ""
		local _err = err and err ~= "" and err or tostring(res and (res.stderr or res.stdout))
		error(_err and _err ~= "" and _err or "Error: Unknown")
		return false
	end

	-- Increase retries every run
	retries = retries + 1
	return mount_device({
		device = device,
		retries = retries,
		max_retry = max_retry,
		password = password,
		username = username,
	})
end

--- Return list of connected devices
---@return Device[]
local function list_gvfs_device()
	---@type Device[]
	local devices = {}
	local _, res = run_command("gio", { "mount", "-li" })
	if res and res.status then
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
local function unmount_gvfs(device, eject, max_retry, retries)
	if not device then
		return true
	end
	max_retry = max_retry or 3
	retries = retries or 0

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
			if retries >= max_retry then
				error(NOTIFY_MSG.UNMOUNT_ERROR, tostring(res and (res.stderr or res.stdout)))
				return false
			end
			return unmount_gvfs(device, eject, max_retry, retries + 1)
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
---@param devices Device|Mount[]
---@return number|nil
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
			{ on = tostring(allow_key_array[idx]), desc = (d.name or "NO_NAME") .. " (" .. d.scheme .. ")" }
		)
	end

	if #cands == 0 then
		return
	end
	local selected_idx = ya.which({
		cands = cands,
	})

	if selected_idx and selected_idx > 0 then
		return selected_idx
	end
end

---@param path string
---@param devices Device[]
---@return Device?
local function get_device_from_path(path, devices)
	local root_mountpoint = get_state(STATE_KEY.ROOT_MOUNTPOINT)
	local scheme, uri = string.match(path, "^" .. root_mountpoint .. "/([^:]+):host=(.+)")
	local domain, user, ssl, prefix, port = nil, nil, nil, nil, nil
	if not uri or not scheme then
		return nil
	end
	if not devices then
		devices = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.MOUNTED)
	end
	if
		scheme == SCHEME.DAV
		or scheme == SCHEME.AFP
		or scheme == SCHEME.DAVS
		or scheme == SCHEME.DAVSD
		or scheme == SCHEME.DAVSSD
		or scheme == SCHEME.FTP
		or scheme == SCHEME.FTPS
		or scheme == SCHEME.FTPIS
		or scheme == SCHEME.GOOGLE_DRIVE
		or scheme == SCHEME.NFS
		or scheme == SCHEME.SFTP
		or scheme == SCHEME.SMB
		or scheme == SCHEME.DNS_SD
	then
		domain, user, ssl, prefix, port = extract_domain_user_from_foldername(scheme .. ":host=" .. uri)
		for _, device in ipairs(devices) do
			local d_scheme, d_domain, d_user, d_ssl, d_prefix, d_port = extract_domain_user_from_uri(device.uri)
			if
				d_scheme:match("^" .. scheme)
				and d_domain == domain
				and d_user == user
				and d_ssl == ssl
				and d_prefix == prefix
				and d_port == port
			then
				return device
			end
			for _, mount in ipairs(device.mounts) do
				d_scheme, d_domain, d_user, d_ssl, d_prefix, d_port = extract_domain_user_from_uri(mount.uri)
				if
					d_scheme:match("^" .. scheme)
					and d_domain == domain
					and d_user == user
					and d_ssl == ssl
					and d_prefix == prefix
					and d_port == port
				then
					return device
				end
			end
		end
	elseif string.find(path, "^" .. GVFS_ROOT_MOUNTPOINT_FILE) then
		local uuid = string.match(path, "^" .. GVFS_ROOT_MOUNTPOINT_FILE .. "/([^/]+)")
		for _, device in ipairs(devices) do
			if device.uuid == uuid then
				return device
			end
		end
	else
		uri = is_literal_string(scheme .. "://" .. uri)
		for _, device in ipairs(devices) do
			if device.uri:match("^" .. uri .. ".*") then
				return device
			end
			for _, mount in ipairs(device.mounts) do
				if mount.uri:match("^" .. uri .. ".*") then
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
		device = #list_devices == 1 and list_devices[1] or list_devices[select_device_which_key(list_devices)]
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
		selected_device = #list_devices == 1 and list_devices[1] or list_devices[select_device_which_key(list_devices)]
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
		selected_device = #list_devices == 1 and list_devices[1] or list_devices[select_device_which_key(list_devices)]
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
	if selected_device.uuid then
		redirect_unmounted_tab_to_home(mount_path)
	end
	local success = unmount_gvfs(selected_device, eject)
	if success and not selected_device.uuid then
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
		if tab_device and tab_device.name == current_tab_device.name then
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

---comment
local save_mounts = function()
	local mounts = get_state(STATE_KEY.MOUNTS)
	local mounts_to_save = {}
	for idx = #mounts, 1, -1 do
		if mounts[idx].is_manually_added then
			-- save name, uri, scheme, is_manually_added
			table.insert(mounts_to_save, 1, {
				name = mounts[idx].name,
				uri = mounts[idx].uri,
				scheme = mounts[idx].scheme,
				is_manually_added = mounts[idx].is_manually_added,
			})
		end
	end

	local save_path = Url(get_state(STATE_KEY.SAVE_PATH))
	-- create parent directories
	local save_path_created, err_create = fs.create("dir_all", save_path.parent)

	if err_create then
		error(NOTIFY_MSG.CANT_CREATE_SAVE_FOLDER, tostring(save_path.parent))
	end

	-- save prefs to file
	if save_path_created then
		local _, err_write = fs.write(save_path, ya.json_encode(mounts))
		if err_write then
			error(NOTIFY_MSG.CANT_SAVE_DEVICES, tostring(save_path))
		end
	end

	-- trigger update to other instances
	broadcast(PUBSUB_KIND.mounts_changed, mounts)
end

local read_mounts_from_saved_file = function(save_path)
	local file = io.open(save_path, "r")
	if file == nil then
		return {}
	end
	local encoded_data = file:read("*all")
	file:close()
	return ya.json_decode(encoded_data)
end

---@param is_edit boolean?
local function add_or_edit_mount_action(is_edit)
	---@type any
	local mount = {
		is_manually_added = true,
	}

	local selected_idx = nil

	if is_edit then
		local mounts = get_state(STATE_KEY.MOUNTS)
		if #mounts == 0 then
			info(NOTIFY_MSG.LIST_MOUNTS_EMPTY)
			return
		end
		selected_idx = select_device_which_key(mounts)
		if not selected_idx then
			return
		end
		mount = tbl_deep_clone(mounts[selected_idx])
	end

	mount.uri, _ = show_input("Enter mount URI:", false, mount.uri)
	if mount.uri == nil then
		return
	elseif mount.uri == "" then
		error(NOTIFY_MSG.URI_CANT_BE_EMPTY)
	end
	mount.uri = mount.uri:gsub("/$", "")
	-- sftp://test@192.168.1.2
	-- ftp://huyhoang@192.168.1.2:9999/
	local _scheme, uri = string.match(mount.uri, "([^:]+)://(.+)")
	local scheme
	if not _scheme or not uri then
		error(NOTIFY_MSG.URI_IS_INVALID)
		return
	end
	for _, value in pairs(SCHEME) do
		if _scheme == value and value ~= SCHEME.FILE then
			scheme = value
		end
	end

	mount.scheme = scheme
	if not scheme then
		error(NOTIFY_MSG.UNSUPPORTED_SCHEME, tostring(_scheme))
		return
	end

	mount.name, _ = show_input("Enter display name:", false, uri)

	if mount.name == nil then
		return
	end

	if mount.name == "" or not mount.name then
		error(NOTIFY_MSG.DISPLAY_NAME_CANT_BE_EMPTY)
		return
	end

	local mounts = get_state(STATE_KEY.MOUNTS)
	if selected_idx then
		Command("gio", { "mount", "-u", mounts[selected_idx].uri })
		mounts[selected_idx] = mount
	else
		table.insert(mounts, mount)
	end
	set_state(STATE_KEY.MOUNTS, mounts)
	save_mounts()
end

local function remove_mount_action()
	local mounts = get_state(STATE_KEY.MOUNTS)
	if #mounts == 0 then
		info(NOTIFY_MSG.LIST_MOUNTS_EMPTY)
		return
	end

	local selected_idx = select_device_which_key(mounts)
	local mount = mounts[selected_idx]
	if not mount then
		return
	end

	run_command("gio", { "mount", "-u", mount.uri })
	table.remove(mounts, selected_idx)
	set_state(STATE_KEY.MOUNTS, mounts)
	save_mounts()
end

---setup function in yazi/init.lua
---@param opts {}
function M:setup(opts)
	if opts and opts.which_keys and type(opts.which_keys) == "string" then
		set_state(STATE_KEY.WHICH_KEYS, opts.which_keys)
	end
	local save_path = (ya.target_family() == "windows" and os.getenv("APPDATA") .. "\\yazi\\config\\gvfs.private")
		or (os.getenv("HOME") .. "/.config/yazi/gvfs.private")
	if type(opts) == "table" then
		save_path = opts.save_path or save_path
	end

	set_state(STATE_KEY.SAVE_PATH, save_path)

	if opts and opts.root_mountpoint and type(opts.root_mountpoint) == "string" then
		set_state(STATE_KEY.ROOT_MOUNTPOINT, opts.root_mountpoint)
	else
		set_state(STATE_KEY.ROOT_MOUNTPOINT, GVFS_ROOT_MOUNTPOINT)
	end
	set_state(STATE_KEY.MOUNTS, read_mounts_from_saved_file(get_state(STATE_KEY.SAVE_PATH)))

	ps.sub_remote(PUBSUB_KIND.mounts_changed, function(mounts)
		set_state(STATE_KEY.MOUNTS, mounts)
	end)
end

---@param job {args: string[], args: {jump: boolean?, eject: boolean?}}
function M:entry(job)
	check_cmd_exist("gio")
	local action = job.args[1]
	-- Select a device then mount
	if action == ACTION.SELECT_THEN_MOUNT then
		local jump = job.args.jump or false
		mount_action({ jump = jump })
		-- select a device then unmount
	elseif action == ACTION.SELECT_THEN_UNMOUNT then
		local eject = job.args.eject or false
		unmount_action(nil, eject)
		-- remount device within current cwd
	elseif action == ACTION.REMOUNT_KEEP_CWD_UNCHANGED then
		remount_keep_cwd_unchanged_action()
		-- select a device then go to its mounted point
	elseif action == ACTION.JUMP_TO_DEVICE then
		jump_to_device_mountpoint_action()
	elseif action == ACTION.JUMP_BACK_PREV_CWD then
		jump_to_prev_cwd_action()
	elseif action == ACTION.ADD_MOUNT then
		add_or_edit_mount_action()
	elseif action == ACTION.EDIT_MOUNT then
		add_or_edit_mount_action(true)
	elseif action == ACTION.REMOVE_MOUNT then
		remove_mount_action()
	end
	ya.render()
end

return M
