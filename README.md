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

Supported protocols: MTP, SMB, SFTP, NFS, GPhoto2 (PIP), FTP, Google Drive, DNS-SD, DAV (WebDAV), AFP, AFC.

Tested: MTP, GPhoto2 (PIP), DAV, SFTP, FTP

By default, `mount` only shows list of devices which has MTP, GPhoto2, AFC, AFP protocols.
To mount other protocols, you need to install corresponding packages and mount them manually.

NOTE: If you have any problems with protocol, please manually mount the device with `gio mount SCHEMES`. [Select Scheme from here](<https://wiki.gnome.org/Projects(2f)gvfs(2f)schemes.html>),
and then create an issue with the output of `gio mount -li` and list of the mount paths under `/run/user/1000/gvfs/XYZ`

## Features

- Mount and unmount device (use `--mount`)
- Can unmount and eject device (use `--eject`)
- Auto jump after successfully mounted a device (use `--jump`)
- Auto select the first device if there is only one device listed.
- Jump to device's mounted location.
- After jumped to device's mounted location, jump back to the previous location
  with a single keybind.
  Make it easier to copy/paste files.

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
   sudo apt install gvfs-backends gvfs-libs gvfs-bin

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
    # This will remount device under cwd (e.g. cwd = $HOME/Media/1_ZTEV5/Downloads/, device mountpoint = $HOME/Media/1_ZTEV5/)
    { on = [ "M", "r" ], run = "plugin gvfs -- remount-current-cwd-device", desc = "Remount device under cwd" },
    { on = [ "M", "u" ], run = "plugin gvfs -- select-then-unmount", desc = "Select device then unmount" },
    # or this if you want to unmount and eject device. Ejected device can safely be removed.
    # Fallback to normal unmount if not supported by device.
    { on = [ "M", "u" ], run = "plugin gvfs -- select-then-unmount --eject", desc = "Select device then eject" },
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
