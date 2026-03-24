# Connect to google drive, onedrive via GNOME ONLINE ACCOUNTS (GOA)

> [!IMPORTANT]
>
> - This is need for google-drive and onedrive to work.
> - Need keyring to be installed (gnome-keyring or kwallet, doesn't need to set `password_vault = "keyring"`). Check [SECURE_SAVED_PASSWORD.md](./SECURE_SAVED_PASSWORD.md) for more information.
> - Because GOA need to open browser to login to your google-drive or onedrive account.
>   So this only works on GUI session. Headless session will not work.
> - Google-drive should work fine now.
>   But to prevent lagging, loading files/folders name in previews panel is disabled.
>   That's mean only current folder and its parent folder is loaded, the preview panel will lazy-load when you enter it.

### Install GNOME Online Accounts (GOA)

```bash
# Ubuntu
sudo apt install gnome-online-accounts gnome-control-center

# Fedora
sudo dnf install gnome-online-accounts gnome-control-center gvfs-goa

# Arch
sudo pacman -S gnome-online-accounts gnome-control-center gvfs-goa

# Gentoo
# Edit /etc/portage/package.use/gvfs.conf again, add more USE flags:
# https://wiki.gentoo.org/wiki/GVfs
gnome-base/gvfs gnome-online-accounts
# Depends on your distro, I disabled all of these USE flags, if you use gnome, you may need to remove them:
gnome-base/gnome-control-center -bluetooth -cups -geolocation -ibus -networkmanager
# Then run this to update gvfs:
sudo emerge -av gnome-base/gvfs net-libs/gnome-online-accounts gnome-base/gnome-control-center
```

### Setup GOA

- Open GOA with this command:

  ```bash
  XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts
  ```

- Select `Google` or `OneDrive` > `Sign in`
- Login via browser. Tick allow access to your Google Drive or OneDrive if asked.
- You account will be added to `Your Accounts` section after login successfully.
- Now you can use `mount` action to mount google-drive or onedrive.

### Remove Account

- Open GOA with this command:

  ```bash
  XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts
  ```

- Select account you want to remove in `Your Accounts` section.
- Click `Remove` button.
