# Connect to google drive, onedrive via GNOME ONLINE ACCOUNTS (GOA)

> [!IMPORTANT]
>
> - This is need for google-drive and onedrive to work.
> - Because GOA need to open browser to login to your google-drive or onedrive account.
>   So this only works on GUI session. Headless session will not work.

> [!IMPORTANT]
>
> After testing google-drive, seems like it is not working very well.
> By default, it will use ID for files, folders instead of name.
> So I will not recommend to use google-drive. Unless you have a good reason.
> You can use rclone to mount instead of gvfs.yazi.

### Install GNOME Online Accounts (GOA)

```bash
# Ubuntu
sudo apt install gnome-online-accounts gnome-control-center

# Fedora (Not tested, please report if it works)
sudo dnf install gnome-online-accounts gnome-control-center gvfs-goa

# Arch
sudo pacman -S gnome-online-accounts gnome-control-center gvfs-goa
```

### Setup GOA

- Open GOA with this command:

  ```bash
  XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts
  ```

- Select `Google` or `OneDrive` > `Sign in`
- Login via browser. Tick allow access to your Google Drive and OneDrive if asked.
- You account will be added to `Your Accounts` section after login successfully.
- Now you can use `mount` action to mount google-drive or onedrive.

### Remove Account

- Open GOA with this command:

  ```bash
  XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts
  ```

- Select account you want to remove in `Your Accounts` section.
- Click `Remove` button.
