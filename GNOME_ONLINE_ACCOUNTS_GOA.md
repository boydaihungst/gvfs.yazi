# Connect to google drive, onedrive via GNOME ONLINE ACCOUNTS (GOA)

> [!IMPORTANT]
>
> - This is need for google-drive and onedrive to work.
> - Because GOA need to open browser to login to your google-drive or onedrive account.
>   So this only works on GUI session. Headless session will not work.

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
- Login via browser. Accept to open GOA from browser.
- You account will be added to `Your Accounts` section after login successfully.
- Now you can use `mount` action to mount google-drive or onedrive.

### Remove Account

- Open GOA with this command:

  ```bash
  XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts
  ```

- Select account you want to remove in `Your Accounts` section.
- Click `Remove` button.
