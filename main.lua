--- @since 25.5.31

local M = {}
local SHELL = os.getenv("SHELL") or ""
local HOME = os.getenv("HOME") or ""
local PLUGIN_NAME = "gvfs"

local USER_ID = ya.uid()
local USER_NAME = tostring(ya.user_name(USER_ID))
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. USER_ID)

local GVFS_ROOT_MOUNTPOINT = XDG_RUNTIME_DIR and (XDG_RUNTIME_DIR .. "/gvfs") or (HOME .. "/.gvfs")
local GVFS_ROOT_MOUNTPOINT_FILE = "/run/media/" .. USER_NAME
local SECRET_TOOL = "secret-tool"
local GPG_TOOL = "gpg"
local PASS_TOOL = "pass"
local SECRET_VAULT_VERSION = "1"

---@enum NOTIFY_MSG
local NOTIFY_MSG = {
	CANT_CREATE_SAVE_FOLDER = "Can't create save folder: %s",
	CANT_SAVE_DEVICES = "Can't write to save file: %s",
	CMD_NOT_FOUND = 'Command "%s" not found. Make sure it is installed.',
	MOUNT_SUCCESS = 'Mounted: "%s"',
	MOUNT_ERROR = "Mount error: %s",
	UNMOUNT_ERROR = "Unmount error: %s",
	UNMOUNT_SUCCESS = 'Unmounted: "%s"',
	EJECT_SUCCESS = 'Ejected "%s", it can safely be removed',
	LIST_DEVICES_EMPTY = "No device or URI found.",
	REMOVED_MOUNT_URI = "Device or URI removed: %s",
	ADDED_MOUNT_URI = "Device or URI added: %s",
	UPDATED_MOUNT_URI = "Device or URI updated: %s",
	DEVICE_IS_DISCONNECTED = "Device or URI is disconnected",
	CANT_ACCESS_PREV_CWD = "Device or URI is disconnected or Previous directory is removed",
	URI_CANT_BE_EMPTY = "URI can't be empty",
	URI_IS_INVALID = "URI is invalid",
	UNSUPPORTED_SCHEME = "Unsupported scheme %s",
	UNSUPPORTED_MANUALLY_MOUNT_SCHEME = "%s scheme is mounted automatically via GNOME Online Accounts (GOA)",
	DISPLAY_NAME_CANT_BE_EMPTY = "Display name can't be empty",
	MOUNT_ERROR_PASSWORD = 'Failed to mount "%s", please check your password',
	MOUNT_ERROR_USERNAME = 'Failed to mount "%s", please check your username',
	HEADLESS_DETECTED = "GVFS.yazi plugin can only run on DBUS session. Check github HEADLESS_WORKAROUND.md to enable DBUS session",
	LIST_MOUNTS_EMPTY = "List mounts URI is empty",
	RETRIVE_PASSWORD_SUCCESS = "Retrieved password from secret vault",
	SAVE_PASSWORD_SUCCESS = "Saved password to secret vault",
	SAVE_PASSWORD_FAILED = "Save password failed: %s",
	SECRET_VAULT_LOCKED = "Secret vault is locked%s",
}

---@enum PASSWORD_VAULT
local PASSWORD_VAULT = {
	KEYRING = "keyring",
	PASS = "pass",
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
	ONE_DRIVE = "onedrive",
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
	CMD_FOUND = "CMD_FOUND",
	DBUS_SESSION = "DBUS_SESSION",
	ROOT_MOUNTPOINT = "ROOT_MOUNTPOINT",
	SAVE_PATH = "SAVE_PATH",
	MOUNTS = "MOUNTS",
	SAVE_PASSWORD_AUTOCONFIRM = "SAVE_PASSWORD_AUTOCONFIRM",
	PASSWORD_VAULT = "PASSWORD_VAULT",
	KEY_GRIP = "KEY_GRIP",
	INPUT_POSITION = "INPUT_POSITION",
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

-- Encode binary string to hex (e.g., "\xED" => "\\xED")
local function hex_encode(s)
	return (s:gsub(".", function(c)
		return string.format("\\x%02X", c:byte())
	end))
end

-- Decode hex-encoded string (e.g., "\\xED" => "\xED")
local function hex_decode(s)
	return (s:gsub("\\x(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function hex_encode_table(t)
	local out = {}
	for k, v in pairs(t) do
		local new_k = type(k) == "string" and hex_encode(k) or k
		local new_v
		if type(v) == "table" then
			new_v = hex_encode_table(v)
		elseif type(v) == "string" then
			new_v = hex_encode(v)
		else
			new_v = v
		end
		out[new_k] = new_v
	end
	return out
end

local function hex_decode_table(t)
	local out = {}
	for k, v in pairs(t) do
		local new_k = type(k) == "string" and hex_decode(k) or k
		local new_v
		if type(v) == "table" then
			new_v = hex_decode_table(v)
		elseif type(v) == "string" then
			new_v = hex_decode(v)
		else
			new_v = v
		end
		out[new_k] = new_v
	end
	return out
end

local set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

local get_state = ya.sync(function(state, key)
	return state[key]
end)
---@param is_password boolean?
local function show_input(title, is_password, value)
	local input_value, input_pw_event = ya.input({
		title = title,
		value = value or "",
		obscure = is_password or false,
		pos = get_state(STATE_KEY.INPUT_POSITION),
		-- TODO: remove this after next yazi released
		position = get_state(STATE_KEY.INPUT_POSITION),
	})
	if input_pw_event ~= 1 then
		return nil, nil
	end
	return input_value, input_pw_event
end

local function error(s, ...)
	ya.notify({ title = PLUGIN_NAME, content = string.format(s, ...), timeout = 3, level = "error" })
end

local function info(s, ...)
	ya.notify({ title = PLUGIN_NAME, content = string.format(s, ...), timeout = 3, level = "info" })
end

---run any command
---@param cmd string
---@param args string[]
---@param _stdin? Stdio|nil
---@return Error|nil, Output|nil
local function run_command(cmd, args, _stdin)
	local stdin = _stdin or Command.INHERIT
	local child, cmd_err = Command(cmd)
		:arg(args)
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stdin(stdin)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()

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

local function is_in_dbus_session()
	local dbus_session = get_state(STATE_KEY.DBUS_SESSION)
	if dbus_session == nil then
		local cha, _ = fs.cha(Url(XDG_RUNTIME_DIR))
		dbus_session = cha and true or false
		set_state(STATE_KEY.DBUS_SESSION, dbus_session)
	end
	return dbus_session
end

local function is_cmd_exist(cmd)
	local cmd_found = get_state(STATE_KEY.CMD_FOUND .. cmd)
	if cmd_found == nil then
		local _, output = run_command("which", { cmd })
		cmd_found = output and output.status and output.status.success
		set_state(STATE_KEY.CMD_FOUND .. cmd, cmd_found)
	end
	return cmd_found
end

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

local function tbl_remove_empty(tbl)
	local cleaned = {}
	for _, v in pairs(tbl) do
		if v ~= nil and v ~= "" then
			table.insert(cleaned, v)
		end
	end
	return cleaned
end

local current_dir = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

---@enum PUBSUB_KIND
local PUBSUB_KIND = {
	mounts_changed = "@" .. PLUGIN_NAME .. "-" .. "mounts-changed",
	unmounted = PLUGIN_NAME .. "-" .. "unmounted",
}

--- broadcast through pub sub to other instances
---@param _ table state
---@param pubsub_kind PUBSUB_KIND
---@param data any
---@param to number default = 0 to all instances
local broadcast = ya.sync(function(_, pubsub_kind, data, to)
	ps.pub_to(to or 0, pubsub_kind, data)
end)

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

local function is_secret_vault_available_keyring(unlock_vault_dialog)
	local res, err = Command(SECRET_TOOL)
		:arg({
			"search",
			PLUGIN_NAME,
			SECRET_VAULT_VERSION,
			unlock_vault_dialog and "--unlock" or nil,
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()

	if err or (res and res.stderr and res.stderr:match("^secret%-tool")) then
		return false
	end
	return true
end

local function build_secret_vault_entry_gpg(protocol, user, domain, prefix, port)
	protocol = protocol and ("/" .. protocol) or ""
	user = user and ("/" .. user) or ""
	domain = domain and ("/" .. domain) or ""
	prefix = prefix and ("/" .. prefix) or ""
	port = port and ("/" .. port) or ""
	return PLUGIN_NAME .. "/" .. SECRET_VAULT_VERSION .. protocol .. user .. domain .. port .. prefix
end

local function is_secret_vault_available_gpg(unlock_vault_dialog, is_second_run)
	local test_vault_entry = build_secret_vault_entry_gpg("test")
	local res, err = Command(SHELL)
		:arg({
			"-c",
			"gpg-connect-agent 'keyinfo " .. get_state(STATE_KEY.KEY_GRIP) .. "' /bye",
		})
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()

	if res then
		-- Case unlocked
		-- S KEYINFO CE3CD21A3A0DCB5EF57B4494AC37127EB207DE6A D - - - P - - -
		-- S KEYINFO 56FB5F16C444102573EF8F1FB666AE48CD39CB4C D - - - C - - -
		if res.stdout:match(".* KEYINFO [^ ]+ .+ .+ .+ 1 ") or res.stdout:match(".* KEYINFO [^ ]+ .+ .+ .+ .+ C ") then
			return true
		elseif unlock_vault_dialog and res.stdout:match(".* KEYINFO [^ ]+ .+ .+ .+ - ") then
			-- Display gpg unlock TUI window
			local permit = ya.hide()
			-- Wrap in shell to capture exit code
			local full_cmd = string.format("bash -c '%s; echo __EXIT__$?__'", "pass " .. test_vault_entry .. " 2>&1")
			local handle = io.popen(full_cmd)
			local output = handle:read("*a")
			handle:close()

			-- Extract exit code
			local exit_code = tonumber(output:match("__EXIT__(%d+)__"))
			output = output:gsub("__EXIT__%d+__", ""):gsub("%s+$", "") -- clean output
			permit:drop()
			if output:match("Error: .* is not in the password store") then
				res, err = Command(SHELL)
					:arg({
						"-c",
						("printf '%s\n%s\n' " .. path_quote("test") .. " " .. path_quote("test") .. " | ")
							.. PASS_TOOL
							.. " insert "
							.. " -f "
							.. path_quote(test_vault_entry),
					})
					:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
					:stderr(Command.PIPED)
					:stdout(Command.PIPED)
					:output()
				if is_second_run or err or (res and res.status and not res.status.success) then
					return false
				end
				return is_secret_vault_available_gpg(unlock_vault_dialog, true)
			end
			return exit_code == 0
		end
	end
	return false
end

local function is_secret_vault_available(unlock_vault_dialog)
	if get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.KEYRING then
		return is_secret_vault_available_keyring(unlock_vault_dialog)
	elseif get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.PASS then
		return is_secret_vault_available_gpg(unlock_vault_dialog)
	end
	return nil
end

local function save_password_keyring(password, protocol, user, domain, prefix, port)
	if not user or not password or not protocol or not domain then
		return false
	end

	local res, err = Command(SHELL)
		:arg({
			"-c",
			("printf %s " .. path_quote(password) .. " | ")
				.. SECRET_TOOL
				.. " store "
				.. " --label "
				.. path_quote(
					protocol
						.. "://"
						.. user
						.. "@"
						.. domain
						.. (port and (":" .. port) or "")
						.. (prefix and ("/" .. prefix) or "")
				)
				.. " "
				.. PLUGIN_NAME
				.. " "
				.. SECRET_VAULT_VERSION
				.. " protocol "
				.. protocol
				.. " user "
				.. path_quote(user)
				.. " domain "
				.. path_quote(domain)
				.. (port and (" port " .. port) or "")
				.. (prefix and (" prefix " .. path_quote(prefix)) or ""),
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()
	if res and res.stderr then
		if res.stderr:match("secret%-tool: Cannot get secret of a locked object") then
			error(NOTIFY_MSG.SECRET_VAULT_LOCKED)
			return false
		elseif res.stderr:match("secret%-tool: The name is not activatable") then
			error(NOTIFY_MSG.HEADLESS_DETECTED)
			return false
		elseif res.stderr:match("secret%-tool: Cannot autolaunch D%-Bus") then
			error(NOTIFY_MSG.HEADLESS_DETECTED)
			return false
		end
	end
	if err or (res and not res.status.success and res.stderr) then
		error(NOTIFY_MSG.SAVE_PASSWORD_FAILED, res and res.stderr or err)
		return false
	end
	info(NOTIFY_MSG.SAVE_PASSWORD_SUCCESS)
	return true
end

local function save_password_gpg(password, protocol, user, domain, prefix, port)
	if not user or not password or not protocol or not domain then
		return false
	end

	local res, err = Command(SHELL)
		:arg({
			"-c",
			("printf '%s\n%s\n' " .. path_quote(password) .. " " .. path_quote(password) .. " | ")
				.. PASS_TOOL
				.. " insert "
				.. " -f "
				.. path_quote(build_secret_vault_entry_gpg(protocol, user, domain, prefix, port)),
		})
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()

	if err or (res and res.status and not res.status.success) then
		error(NOTIFY_MSG.SAVE_PASSWORD_FAILED, res and res.stderr or err)
		return false
	end

	info(NOTIFY_MSG.SAVE_PASSWORD_SUCCESS)
	return true
end

local function save_password(password, protocol, user, domain, prefix, port)
	if get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.KEYRING then
		return save_password_keyring(password, protocol, user, domain, prefix, port)
	elseif get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.PASS then
		return save_password_gpg(password, protocol, user, domain, prefix, port)
	end
	return false
end

local function lookup_password_keyring(protocol, user, domain, prefix, port)
	if not user or not protocol or not domain then
		return nil
	end
	local res, err = Command(SECRET_TOOL)
		:arg({
			"lookup",
			PLUGIN_NAME,
			SECRET_VAULT_VERSION,
			"protocol",
			protocol,
			"user",
			user,
			"domain",
			domain,
			port and "port" or nil,
			port and port or nil,
			prefix and "prefix" or nil,
			prefix and prefix or nil,
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()
	if not err and res and res.status and res.status.success then
		return res.stdout
	end

	return nil
end

local function lookup_password_gpg(protocol, user, domain, prefix, port)
	if not user or not protocol or not domain then
		return nil
	end
	local res, err = Command(PASS_TOOL)
		:arg({
			build_secret_vault_entry_gpg(protocol, user, domain, prefix, port),
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()
	if not err and res and res.status and res.status.success then
		return res.stdout
	end

	return nil
end

local function lookup_password(protocol, user, domain, prefix, port)
	if get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.KEYRING then
		return lookup_password_keyring(protocol, user, domain, prefix, port)
	elseif get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.PASS then
		return lookup_password_gpg(protocol, user, domain, prefix, port)
	end
	return nil
end

local function clear_password_keyring(protocol, user, domain, prefix, port)
	local res, err = Command(SECRET_TOOL)
		:arg({
			"clear",
			PLUGIN_NAME,
			SECRET_VAULT_VERSION,
			protocol and "protocol" or nil,
			protocol and protocol or nil,
			user and "user" or nil,
			user and user or nil,
			domain and "domain" or nil,
			domain and domain or nil,
			port and "port" or nil,
			port and port or nil,
			prefix and "prefix" or nil,
			prefix and prefix or nil,
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()
	if res and res.stderr and not res.status.success then
		if res.stderr:match("secret%-tool: Cannot get secret of a locked object") then
			error(NOTIFY_MSG.SECRET_VAULT_LOCKED)
			return false
		elseif res.stderr:match("secret%-tool: The name is not activatable") then
			error(NOTIFY_MSG.HEADLESS_DETECTED)
			return false
		elseif res.stderr:match("secret%-tool: Cannot autolaunch D%-Bus") then
			error(NOTIFY_MSG.HEADLESS_DETECTED)
			return false
		end
	end

	if not err and res and res.status and res.status.success then
		return true
	end
	return false
end

local function clear_password_gpg(protocol, user, domain, prefix, port)
	-- pass rm -r -f gvfs/test1
	local res, err = Command(PASS_TOOL)
		:arg({
			"rm",
			"-r",
			"-f",
			build_secret_vault_entry_gpg(protocol, user, domain, prefix, port),
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()
	if not err and res and res.status and res.status.success then
		return true
	end
	return false
end

local function clear_password(protocol, user, domain, prefix, port)
	if get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.KEYRING then
		return clear_password_keyring(protocol, user, domain, prefix, port)
	elseif get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.PASS then
		return clear_password_gpg(protocol, user, domain, prefix, port)
	end
	return false
end

local function extract_domain_user_from_uri(s)
	local user
	local domain
	local port

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
			port = nil
			domain = temp_domain_part:match("^[^/]+") or temp_domain_part
		end
	else
		-- Attempt 2: No user@domain, so try to get domain from the start (before first comma or slash)
		-- davs://domain/dav
		scheme, temp_domain_part = s:match("^([^:]+)://([^/]+)")
		if temp_domain_part then
			domain, port = temp_domain_part:match("^([^:/]+):([^:/]+)")
			if not port or port == "" then
				port = nil
				domain = temp_domain_part:match("^[^/]+") or temp_domain_part
			end
		end
	end

	local ssl = (s:match("^davs") or s:match("^ftps") or s:match("^ftpis") or s:match("^https")) and true or false
	local prefix = s:match(".*" .. (domain or "") .. (port and ":" .. port or "") .. "/(.+)$") or nil
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
	local user
	local domain
	local ssl = false
	local prefix
	local scheme
	local port
	scheme, s = s:match("^([^:]+):(.+)")

	for part in s:gmatch("([^,]+)") do
		if part:match("^host=(.+)") then
			domain = part:match("^host=([^,/]+)")
		end
	end
	domain = uri_decode(s:match("^host=([^,]+)"))
	user = uri_decode(s:match(".*user=([^,]+)"))
	ssl = s:match(".*ssl=true") and true or false
	prefix = uri_decode(s:match(".*prefix=([^,]+)"))
	port = s:match(".*port=([^,]+)")
	if prefix then
		prefix = prefix:match("/(.+)")
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
				if mount_uri:match("^" .. is_literal_string(value) .. ":") then
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
		-- local scheme, uri = string.match(path, "^" .. root_mountpoint .. "/([^:]+):host=(.+)")
		if v.uuid and not v.uuid:match("([^:]+)://(.+)") then
			v.scheme = SCHEME.FILE
		else
			for _, value in pairs(SCHEME) do
				if
					(v.uri and v.uri:match("^" .. is_literal_string(value) .. ":"))
					or (v.uuid and v.uuid:match("^" .. is_literal_string(value) .. "://"))
				then
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
		or target.scheme == SCHEME.ONE_DRIVE
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
				scheme
				and f_scheme
				and scheme:match("^" .. is_literal_string(f_scheme))
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
	if device and device.mounts and #device.mounts > 0 then
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
---@param opts {device: Device,username?:string, password?: string, is_pw_saved?: boolean, skipped_secret_vault?: boolean,max_retry?: integer, retries?: integer}
---@return boolean
local function mount_device(opts)
	local device = opts.device
	local max_retry = opts.max_retry or 3
	local retries = opts.retries or 0
	local password = opts.password
	local is_pw_saved = opts.is_pw_saved
	local skipped_secret_vault = opts.skipped_secret_vault
	local username = opts.username
	local error_msg = nil

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

	local res, err = Command(SHELL)
		:arg({
			"-c",
			(auth_string_format ~= "" and "printf " .. path_quote(auth_string_format) .. " " .. auths .. " | " or "")
				.. " gio mount "
				.. (device.uuid and ("-d " .. device.uuid) or path_quote(device.uri)),
		})
		:env("XDG_RUNTIME_DIR", XDG_RUNTIME_DIR)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()

	local mount_success = res and res.status and res.status.success

	if mount_success then
		info(NOTIFY_MSG.MOUNT_SUCCESS, device.name)
		if password and not is_pw_saved and not skipped_secret_vault and is_secret_vault_available() then
			local confirmed_save_password = get_state(STATE_KEY.SAVE_PASSWORD_AUTOCONFIRM)
				or ya.confirm({
					title = ui.Line("Remember password?"):style(th.confirm.title),
					body = ui.Text({
						ui.Line(""),
						ui.Line("Press Yes to save password to secret vault."):style(th.confirm.content),
						ui.Line(""),
					})
						:align(ui.Align.CENTER)
						:wrap(ui.Wrap.YES),
					-- TODO: remove this after next yazi released
					content = ui.Text({
						ui.Line(""),
						ui.Line("Press Yes to save password to secret vault."):style(th.confirm.content),
						ui.Line(""),
					})
						:align(ui.Align.CENTER)
						:wrap(ui.Wrap.YES),
					pos = { "center", w = 70, h = 10 },
				})

			if confirmed_save_password then
				local scheme, domain, user, _, prefix, port = extract_domain_user_from_uri(device.uri)
				save_password(password, scheme, username or user, domain, prefix, port)
			end
		end
		return true
	elseif res and res.status.code == 2 then
		if res.stderr:match(".*volume doesn’t implement mount.*") then
			error_msg = string.format(NOTIFY_MSG.HEADLESS_DETECTED)
			retries = max_retry
		end
		if res.stdout:find("Authentication Required") then
			local stdout = res.stdout:match(".*Authentication Required(.*)") or ""
			if stdout:find("\nUser: \n") then
				if retries < max_retry then
					username, _ =
						show_input("Enter username " .. (device.uri and "(" .. device.uri .. ")" or "") .. ":", false)
					if username == nil then
						return false
					end
				else
					error_msg = string.format(
						NOTIFY_MSG.MOUNT_ERROR_USERNAME,
						(device.name or "NO_NAME") .. " (" .. device.scheme .. ")"
					)
				end
			end
			if stdout:find("\nPassword: \n") or stdout:find("\nUser: \n") or stdout:find("\nUser %[.*%]: \n") then
				if username ~= opts.username or (username == nil and is_pw_saved == nil) then
					-- Prevent showing gpg passphrase twice
					if not is_secret_vault_available(true) then
						skipped_secret_vault = true
					end
					if not skipped_secret_vault then
						local scheme, domain, user, _, prefix, port = extract_domain_user_from_uri(device.uri)
						password = lookup_password(scheme, username or user, domain, prefix, port)
						is_pw_saved = password ~= nil
						if is_pw_saved then
							info(NOTIFY_MSG.RETRIVE_PASSWORD_SUCCESS)
						end
					end
				end
				if retries < max_retry then
					if not is_pw_saved then
						password, _ = show_input(
							"Enter password " .. (device.uri and "(" .. device.uri .. ")" or "") .. ":",
							true
						)
						if password == nil then
							return false
						end
					end
				else
					error_msg = string.format(
						NOTIFY_MSG.MOUNT_ERROR_PASSWORD,
						(device.name or "NO_NAME") .. " (" .. device.scheme .. ")"
					)
				end
			end
		end
	end
	-- show notification after get max retry
	if retries >= max_retry then
		error(error_msg or (res and not res.status.success and res.stderr) or err or "Error: Unknown")
		return false
	end

	-- Increase retries every run
	retries = retries + 1
	return mount_device({
		device = device,
		retries = retries,
		max_retry = max_retry,
		password = password,
		is_pw_saved = is_pw_saved,
		skipped_secret_vault = skipped_secret_vault,
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
---@param force boolean? Ignore outstanding file operations when unmounting or ejecting
---@return boolean
local function unmount_gvfs(device, eject, force, max_retry, retries)
	if not device then
		return true
	end
	max_retry = max_retry or 3
	retries = retries or 0

	local unmount_method = "-u"
	if eject then
		unmount_method = "-e"
	end
	for _, mount in ipairs(device.mounts ~= nil and device.mounts or { device }) do
		local cmd_err, res =
			run_command("gio", tbl_remove_empty({ "mount", unmount_method, force and "-f" or nil, mount.uri }))
		if cmd_err or (res and not res.status.success) then
			if eject and res and res.stderr:find("mount doesn.*t implement .*eject.* or .*eject_with_operation.*") then
				return unmount_gvfs(device, false, force)
			end
			if retries >= max_retry then
				error(NOTIFY_MSG.UNMOUNT_ERROR, tostring(res and (res.stderr or res.stdout)))
				return false
			end
			return unmount_gvfs(device, eject, force, max_retry, retries + 1)
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
	local scheme, uri = string.match(path, "^" .. is_literal_string(root_mountpoint) .. "/([^:]+):host=(.+)")
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
		or scheme == SCHEME.ONE_DRIVE
		or scheme == SCHEME.NFS
		or scheme == SCHEME.SFTP
		or scheme == SCHEME.SMB
		or scheme == SCHEME.DNS_SD
	then
		domain, user, ssl, prefix, port = extract_domain_user_from_foldername(scheme .. ":host=" .. uri)
		for _, device in ipairs(devices) do
			local d_scheme, d_domain, d_user, d_ssl, d_prefix, d_port = extract_domain_user_from_uri(device.uri)
			if
				d_scheme
				and d_scheme:match("^" .. is_literal_string(scheme))
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
					d_scheme
					and d_scheme:match("^" .. is_literal_string(scheme))
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
	elseif string.find(path, "^" .. is_literal_string(GVFS_ROOT_MOUNTPOINT_FILE)) then
		local uuid = string.match(path, "^" .. is_literal_string(GVFS_ROOT_MOUNTPOINT_FILE) .. "/([^/]+)")
		for _, device in ipairs(devices) do
			if device.uuid == uuid then
				return device
			end
		end
	else
		uri = is_literal_string(scheme .. "://" .. uri)
		for _, device in ipairs(devices) do
			if device.uri:match("^" .. is_literal_string(uri) .. ".*") then
				return device
			end
			for _, mount in ipairs(device.mounts) do
				if mount.uri:match("^" .. is_literal_string(uri) .. ".*") then
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
		info(NOTIFY_MSG.LIST_DEVICES_EMPTY)
		return
	end
	local mnt_point = get_mount_path(device)
	-- local success = is_mounted(device)

	if mnt_point ~= "" then
		set_state(STATE_KEY.PREV_CWD, current_dir())
		ya.emit("cd", { mnt_point, raw = true })
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
		ya.emit("cd", { prev_cwd, raw = true })
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
				info(NOTIFY_MSG.LIST_DEVICES_EMPTY)
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

local redirect_unmounted_tab_to_home = ya.sync(function(_, unmounted_url, notify)
	if not unmounted_url or unmounted_url == "" then
		return
	end
	-- broadcast to other instances
	if notify then
		broadcast(PUBSUB_KIND.unmounted, hex_encode(unmounted_url))
	end
	for _, tab in ipairs(cx.tabs) do
		if tab.current.cwd:starts_with(unmounted_url) then
			ya.emit("cd", {
				HOME,
				tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
				raw = true,
			})
		end
	end
end)

--- unmount action
--- @param device Device?
--- @param eject boolean? eject = true if user want to safty unplug the device
--- @param force boolean? Ignore outstanding file operations when unmounting or ejecting
local function unmount_action(device, eject, force)
	local selected_device
	if not device then
		local list_devices = list_gvfs_device_by_status(DEVICE_CONNECT_STATUS.MOUNTED)
		-- NOTE: Automatically select the first device if there is only one device
		selected_device = #list_devices == 1 and list_devices[1] or list_devices[select_device_which_key(list_devices)]
		if not selected_device and #list_devices == 0 then
			info(NOTIFY_MSG.LIST_DEVICES_EMPTY)
		end
	end
	if device then
		selected_device = device
	end
	if not selected_device then
		info(NOTIFY_MSG.LIST_DEVICES_EMPTY)
		return
	end

	local mount_path = get_mount_path(selected_device)
	if selected_device.uuid then
		redirect_unmounted_tab_to_home(mount_path, true)
	end
	local success = unmount_gvfs(selected_device, eject, force)
	if success and not selected_device.uuid then
		redirect_unmounted_tab_to_home(mount_path, true)
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
				raw = true,
			})
		end
	end
	mount_action({ jump = false, device = current_tab_device })
	for _, tab in ipairs(saved_matched_tabs) do
		ya.emit("cd", {
			tostring(tab.cwd),
			tab = tab.id,
			raw = true,
		})
	end
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

	-- save mounts to file
	if save_path_created then
		local _, err_write = fs.write(save_path, ya.json_encode(hex_encode_table(mounts)))
		if err_write then
			error(NOTIFY_MSG.CANT_SAVE_DEVICES, tostring(save_path))
		end
	end

	-- trigger update to other instances
	broadcast(PUBSUB_KIND.mounts_changed, hex_encode_table(mounts))
end

local read_mounts_from_saved_file = function(save_path)
	local file = io.open(save_path, "r")
	if file == nil then
		return {}
	end
	local encoded_data = file:read("*all")
	file:close()
	return hex_decode_table(ya.json_decode(encoded_data))
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
	if scheme == SCHEME.GOOGLE_DRIVE or scheme == SCHEME.ONE_DRIVE then
		error(NOTIFY_MSG.UNSUPPORTED_MANUALLY_MOUNT_SCHEME, tostring(_scheme))
		return
	end

	mount.name, _ = show_input("Enter display name:", false, mount.name or uri)

	if mount.name == nil then
		return
	end

	if mount.name == "" or not mount.name then
		error(NOTIFY_MSG.DISPLAY_NAME_CANT_BE_EMPTY)
		return
	end

	local mounts = get_state(STATE_KEY.MOUNTS)
	if selected_idx then
		if is_mounted(mounts[selected_idx]) then
			unmount_action(mounts[selected_idx], false, true)
		end
		if mount.uri ~= mounts[selected_idx].uri then
			local old_scheme, old_domain, old_user, _, old_prefix, old_port =
				extract_domain_user_from_uri(mounts[selected_idx].uri)
			if old_domain and old_scheme and is_secret_vault_available(true) then
				clear_password(old_scheme, old_user, old_domain, old_prefix, old_port)
			end
		end
		mounts[selected_idx] = mount
		info(NOTIFY_MSG.UPDATED_MOUNT_URI, mount.name)
	else
		table.insert(mounts, mount)
		info(NOTIFY_MSG.ADDED_MOUNT_URI, mount.name)
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

	if is_mounted(mount) then
		unmount_action(mount, false, true)
	end
	-- run_command("gio", { "mount", "-u", mount.uri })
	local old_scheme, old_domain, old_user, _, old_prefix, old_port =
		extract_domain_user_from_uri(mounts[selected_idx].uri)
	if old_domain and old_scheme and is_secret_vault_available(true) then
		clear_password(old_scheme, old_user, old_domain, old_prefix, old_port)
	end
	local removed_mount = table.remove(mounts, selected_idx)
	set_state(STATE_KEY.MOUNTS, mounts)
	info(NOTIFY_MSG.REMOVED_MOUNT_URI, removed_mount.name)
	save_mounts()
end

---setup function in yazi/init.lua
---@param opts {}
function M:setup(opts)
	if opts and opts.key_grip then
		set_state(STATE_KEY.KEY_GRIP, opts.key_grip)
	end
	set_state(
		STATE_KEY.INPUT_POSITION,
		opts and type(opts.input_position) == "table" and opts.input_position or { "top-center", y = 3, w = 60 }
	)
	if opts and opts.save_password_autoconfirm == true then
		set_state(STATE_KEY.SAVE_PASSWORD_AUTOCONFIRM, true)
	end
	if opts and opts.password_vault then
		set_state(
			STATE_KEY.PASSWORD_VAULT,
			(opts and (opts.password_vault == PASSWORD_VAULT.KEYRING or opts.password_vault == PASSWORD_VAULT.PASS))
				and opts.password_vault
		)
	else
		-- TODO: REMOVE: backwards compatibility
		if opts and opts.enabled_keyring == true then
			set_state(STATE_KEY.PASSWORD_VAULT, PASSWORD_VAULT.KEYRING)
		end
	end

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
		set_state(STATE_KEY.MOUNTS, hex_decode_table(mounts))
	end)
	ps.sub_remote(PUBSUB_KIND.unmounted, function(unmounted_url)
		redirect_unmounted_tab_to_home(hex_decode(unmounted_url))
	end)
end

---@param job {args: string[], args: {jump: boolean?, eject: boolean?, force: boolean?}}
function M:entry(job)
	if not is_cmd_exist("gio") then
		error(NOTIFY_MSG.CMD_NOT_FOUND, "gio")
		return
	end
	-- Fallback to pass if in headless session
	if not is_in_dbus_session() then
		error(NOTIFY_MSG.HEADLESS_DETECTED)
		return
	end

	if get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.KEYRING then
		if not is_cmd_exist(SECRET_TOOL) then
			set_state(STATE_KEY.PASSWORD_VAULT, nil)
		end
	end
	if get_state(STATE_KEY.PASSWORD_VAULT) == PASSWORD_VAULT.PASS then
		if not is_cmd_exist(GPG_TOOL) or not is_cmd_exist(PASS_TOOL) or get_state(STATE_KEY.KEY_GRIP) == nil then
			set_state(STATE_KEY.PASSWORD_VAULT, nil)
		end
	end
	local action = job.args[1]
	-- Select a device then mount
	if action == ACTION.SELECT_THEN_MOUNT then
		local jump = job.args.jump or false
		mount_action({ jump = jump })
		-- select a device then unmount
	elseif action == ACTION.SELECT_THEN_UNMOUNT then
		local eject = job.args.eject or false
		local force = job.args.force or false
		unmount_action(nil, eject, force)
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
