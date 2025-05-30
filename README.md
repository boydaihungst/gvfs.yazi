# gvfs.yazi

<!--toc:start-->

- [gvfs.yazi](#gvfsyazi)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Usage](#usage)
  <!--toc:end-->

[gvfs.yazi](https://github.com/boydaihungst/gvfs.yazi) uses [gvfs](https://wiki.gnome.org/Projects/gvfs) and [gio from glib](https://github.com/GNOME/glib) to transparently mount and unmount devices in read/write mode,
allowing you to navigate inside, view, and edit individual or groups of files.

Supported protocols: MTP, Hard disk/drive, SMB, SFTP, NFS, GPhoto2 (PTP), FTP, Google Drive, DNS-SD, DAV (WebDAV), AFP, AFC.
You need to install corresponding packages to use them.

Tested: MTP, Hard disk/drive, GPhoto2 (PTP), DAV, SFTP, FTP. You may need to unlock and turn screen on to mount some devices (Android MTP, etc.)

By default, `mount` will shows list of devices which have MTP, GPhoto2, AFC protocols or mount URIs for other protocols.
For other protocols (smb, ftp, sftp, etc), add mount URIs using `add-mount` action. See more in the keymap below.

NOTE:

- If you have any problems with protocol, please manually mount the device with `gio mount SCHEMES`. [Select Scheme from here](<https://wiki.gnome.org/Projects(2f)gvfs(2f)schemes.html>),
  and then create an issue with the output of `gio mount -li` and list of the mount paths under `/run/user/1000/gvfs/XYZ`

- Trash won't work on some protocols, use permanently delete instead.

- SCHEMES URI shouldn't contain password, because it's saved as plaintext in `yazi/config/gvfs.private`.


## Preview

https://github.com/user-attachments/assets/9e9df85c-d8d6-4b97-b978-614965d3b218

## Features

- Support all gvfs schemes (mtp, smb, ftp, sftp, nfs, gphoto2, afp, afc, sshfs, dav, davs, dav+sd, davs+sd, dns-sd)
- Mount device (use `--mount`)
- Can unmount and eject device (use `--eject`)
- Auto jump to device mounted location after successfully mounted (use `--jump`)
- Auto select the first device if there is only one device listed.
- Jump to device's mounted location (use `jump-to-device`)
- After jumped to device's mounted location, jump back to the previous location
  with a single keybind. Make it easier to copy/paste files. (use `jump-back-prev-cwd`)
- Add/Edit/Remove mountpoint (use `add-mount`, `edit-mount`, `remove-mount`). The URI of the mountpoint follow these schemes: [schemes.html](<https://wiki.gnome.org/Projects(2f)gvfs(2f)schemes.html>)

## Requirements

1. [yazi >= 25.5.28](https://github.com/sxyazi/yazi)

2. This plugin only supports Linux, and requires having [GLib](https://github.com/GNOME/glib), [gvfs](https://gitlab.gnome.org/GNOME/gvfs)

   ```sh
   # Ubuntu
   sudo apt install gvfs libglib2.0-dev

   # Fedora
   sudo dnf install gvfs glib2-devel

   # Arch
   sudo pacman -S gvfs glib2
   ```

3. And other `gvfs` protocol packages, choose what you need, all of them are optional:

   ```sh
   # Ubuntu
   sudo apt install gvfs-backends gvfs-libs

   # Fedora
   sudo dnf install gvfs-mtp gvfs-archive gvfs-goa gvfs-gphoto2 gvfs-smb gvfs-afc gvfs-dnssd

   # Arch
   sudo pacman -S gvfs-mtp gvfs-afc gvfs-google gvfs-gphoto2 gvfs-nfs gvfs-smb gvfs-afc gvfs-dnssd gvfs-goa gvfs-onedrive gvfs-wsdd
   ```

For other distros please ask gemini.

## Installation

```sh
ya pkg add boydaihungst/gvfs
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("gvfs"):setup({
  -- (Optional) Allowed keys to select device.
  which_keys = "1234567890qwertyuiopasdfghjklzxcvbnm-=[]\\;',./!@#$%^&*()_+{}|:\"<>?",

  -- (Optional) Save file.
  -- Default: ~/.config/yazi/gvfs.private
  save_path = os.getenv("HOME") .. "/.config/yazi/gvfs.private"
})
```

## Usage

Add this to your `~/.config/yazi/keymap.toml`:

```toml
[manager]
prepend_keymap = [
    # simple-mtpfs plugin
    { on = [ "M", "m" ], run = "plugin gvfs -- select-then-mount", desc = "Select device then mount" },
    # or this if you want to jump to mountpoint after mounted
    { on = [ "M", "m" ], run = "plugin gvfs -- select-then-mount --jump", desc = "Select device to mount and jump to its mount point" },
    # This will remount device under cwd (e.g. cwd = /run/user/1000/gvfs/DEVICE_1/FOLDER_A, device mountpoint = /run/user/1000/gvfs/DEVICE_1)
    { on = [ "M", "R" ], run = "plugin gvfs -- remount-current-cwd-device", desc = "Remount device under cwd" },
    { on = [ "M", "u" ], run = "plugin gvfs -- select-then-unmount", desc = "Select device then unmount" },
    # or this if you want to unmount and eject device. Ejected device can safely be removed.
    # Fallback to normal unmount if not supported by device.
    { on = [ "M", "u" ], run = "plugin gvfs -- select-then-unmount --eject", desc = "Select device then eject" },

    # Add|Edit|Remove mountpoint: smb, sftp, ftp, nfs, google-drive, dns-sd, dav, davs, dav+sd, davs+sd, afp, afc, sshfs
    # Read more about the schemes here: https://wiki.gnome.org/Projects(2f)gvfs(2f)schemes.html
    # For example: smb://user:password@192.168.1.2/share, sftp://user@192.168.1.2/, ftp://192.168.1.2/
    { on = [ "M", "a" ], run = "plugin gvfs -- add-mount", desc = "Add a GVFS mount URI" },
    { on = [ "M", "e" ], run = "plugin gvfs -- edit-mount", desc = "Edit a GVFS mount URI" },
    { on = [ "M", "r" ], run = "plugin gvfs -- remove-mount", desc = "Remove a GVFS mount URI" },

    # Jump
    { on = [ "g", "m" ], run = "plugin gvfs -- jump-to-device", desc = "Select device then jump to its mount point" },
    { on = [ "`", "`" ], run = "plugin gvfs -- jump-back-prev-cwd", desc = "Jump back to the position before jumped to device" },
]
```

It's highly recommended to add these lines to your `~/.config/yazi/yazi.toml`,
because GVFS is slow that can make yazi freeze when it preload and previews a large number of files.
Replace `1000` with your real user id (run `id -u` to get user id).

```toml
[plugin]
preloaders = [
  # Do not preload gvfs mount_point
  # Environment variable won't work here.
  # Using absolute path instead.
  { name = "/run/user/1000/gvfs/**/*", run = "noop" },
  #... the rest of preloaders
]
previewers = [
  # Allow to preview folder.
  { name = "*/", run = "folder", sync = true },
  # Do not preview MTP mount_point (uncomment to except text file)
  #  { mime = "{text/*,application/x-subrip}", run = "code" },
  # Using absolute path.
  { name = "/run/user/1000/gvfs/**/*", run = "noop" },
  #... the rest of previewers
]
```
