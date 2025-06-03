# There are two methods to securely store passwords

<!--toc:start-->

- [There are two methods to securely store passwords](#there-are-two-methods-to-securely-store-passwords)
  - [Method 1. Use `secret-tool` with `Keyring` (Gnome Keyring or KWallet).](#method-1-use-secret-tool-with-keyring-gnome-keyring-or-kwallet)
  - [Method 2. Use `pass` (Password Store) with `GPG` encryption subkey](#method-2-use-pass-password-store-with-gpg-encryption-subkey)
  <!--toc:end-->

If you don't want to re-enter passwords everytime connect to a saved scheme/mount URI (SMB, FTP, etc), you can use `Keyring` + `secret-tool` or `pass` + `GPG` to store passwords. `Keyring` can only be use in GUI session, `GPG` can use in both Headless and GUI session.

## Method 1. Use `secret-tool` with `Keyring` (Gnome Keyring or KWallet).

Best for GUI users.
If you need to use headless workaround (see [HEADLESS_WORKAROUND.md](./HEADLESS_WORKAROUND.md)), you can only use [Method 2. Use `pass` (Password Store) with GPG encryption subkey](#2-use-pass-password-store-with-gpg-encryption-subkey).

- Install `secret-tool`:

  ```sh
  # Ubuntu
  sudo apt install libsecret-tools

  # Fedora (Not tested, please report if it works)
  sudo dnf install libsecret

  # Arch
  sudo pacman -S libsecret
  ```

- Install `GNOME-Keyring` (or KWallet)

  ```sh
  # Ubuntu
  sudo apt install gnome-keyring
  # Ubuntu GNOME already starts the keyring daemon automatically.
  # If you're using another DE or a window manager, see manual startup notes below.

  # Fedora (Not tested, please report if it works)
  sudo dnf install gnome-keyring
  # Fedora Workstation (GNOME) starts the daemon automatically.
  # If you're using another DE or a window manager, see manual startup notes below.

  # Arch
  sudo pacman -S gnome-keyring
  sudo systemctl enable --now --user gnome-keyring-daemon
  ```

  For other distros please ask gemini/chatgpt.

- Manual Startup `gnome-keyring` if need
  Check if it's running: `pgrep -fl gnome-keyring-daemon`. Skip this step if it's already running.
  If you're using i3, Xfce, sway, hyprland or another WM. [Read more](<https://wiki.archlinux.org/title/GNOME/Keyring#Using_gnome-keyring-daemon_outside_desktop_environments_(KDE,_GNOME,_XFCE,_...)>)
  Add this to your session startup (e.g., .xinitrc, ~/.xprofile, or your DE’s autostart system):

  ```sh
  # Start gnome-keyring
  eval $(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh)
  ```

  Or copy `~/.config/yazi/plugins/gvfs.yazi/assets/gnome-keyring-daemon.service` to `~/.config/systemd/user/` and run:

  ```bash
  systemctl --user daemon-reload
  systemctl --user enable --now gnome-keyring-daemon.service
  ```

- Add `password_vault = "keyring"` to setup function in `~/.config/yazi/init.lua`:

```lua
require("gvfs"):setup({
  password_vault = "keyring",
})
```

Now you can use gvfs.yazi and save passwords to the keyring.
You only need to unlock the keyring once after login or after trigger gvfs.yazi plugin.

- You can also auto unlock the keyring with PAM:
  - [Gnome Keyring Auto Unlock on login](https://wiki.archlinux.org/title/GNOME/Keyring#Using_the_keyring)
  - [Kwallet Auto Unlock on login](https://wiki.archlinux.org/title/KDE_Wallet#Unlock_KDE_Wallet_automatically_on_login)

> [!IMPORTANT]
> If you want to clear saved passwords, you can run these commands in terminal:

```bash
secret-tool search --all --unlock gvfs 1
secret-tool clear gvfs 1
```

## Method 2. Use `pass` (Password Store) with `GPG` encryption subkey

The only option for headless users.
Can use on both GUI and headless session (non-active console, Like connect to a computer via SSH, etc).

- Install `pass` and `gpg`

  ```bash
  # Ubuntu
  sudo apt install pass gnupg

  # Fedora (Not tested, please report if it works)
  sudo dnf install pass gnupg2

  # Arch
  sudo pacman -S pass gnupg
  ```

  For other distros please ask gemini/chatgpt.

- Create a GPG key for encryption (Ignore if you already have a GPG key)

  ```bash
  gpg --full-generate-key
  ```

- Select `ECC (sign and encrypt)` and then select `Curve 25519` and `0 = key does not expire`. Usually you only need to press enter 3 times.
  Then press `y` and `enter` to confirm. Enter name, email, comment, and passphrase. Remember the passphrase, which will be used for unlocking the key. Empty passphrase is also support but discouraged.

- Get the `<KEY_ID>` and `KEY_GRIP` of created GPG key:

  ```bash
  gpg --list-secret-keys --keyid-format LONG --with-keygrip
  ```

  Result should look like this:

  ```bash
  sec   ed25519/xxxxxxxxxxxxx 2025-06-02 [SC]
        yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
        Keygrip = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
  uid                 [ultimate] test <test@example.com>
  ssb   cv25519/zzzzzzzzzzzzz 2025-06-02 [E]
        Keygrip = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
  ```

  Subkey for encryption is the one ends with `[E]`

  => `<KEY_ID>` is `zzzzzzzzzzzzz` and `<KEY_GRIP>` is `BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB`

  There can be multiple subkeys, but we only need one.

- Initialize the password store:

  ```bash
  # Re-run this with new <KEY_ID>, saved passwords will auto transfer to new one.
  pass init <KEY_ID>
  ```

- Add the `<KEY_GRIP>` and `password_vault` to setup function in `~/.config/yazi/init.lua`:

  ```lua
  require("gvfs"):setup({
    key_grip = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
    password_vault = "pass",
  })
  ```

> [!IMPORTANT]
> Using `password_vault = "pass"` without `key_grip`, gvfs.yazi won't be able to save passwords to the password store.
> GPG Keygrip IS NOT secret and does not need to be kept private.
> So you can share your config file without worrying about leaking your passwords.

Now you can use gvfs.yazi and save passwords to the password store.
To increase the time gpg-agent cache the passwords: https://wiki.archlinux.org/title/GnuPG#Cache_passwords

> [!IMPORTANT]
> If you want to clear saved passwords, you can run these commands in terminal:

```bash
# Clear all saved passwords
pass rm -r gvfs -f
# Reset unlock state of GPG key
gpgconf --kill gpg-agent
```
