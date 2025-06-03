# Headless Workaround to start D-bus session

<!--toc:start-->

- [Headless Workaround to start D-bus session](#headless-workaround-to-start-d-bus-session)
<!--toc:end-->

> [!IMPORTANT]
>
> - Only apply this workaround if you see this error message: `GVFS.yazi can only run on DBUS session`.
> - For headless session only, non-active console, like connect to a computer via SSH, etc.
> - For systemd users only. Most mainstream distros use systemd by default.
> - You only need to do this once.
> - Mount a hardware device (Hard disk/drive, etc) may encounter permission denied error. Refer to custom polkit section to fix it.

### Step 1: Connect to the target computer.

### Step 2: Run this command in the target computer terminal:

```bash
# Start systemd user session if not already running
sudo loginctl enable-linger $(whoami)
```

### Step 3: Reboot.

### Step 4: (Optional) Add custom polkit rule to fix permission denied error when mounting a hardware device (Hard disk/drive, etc)

```bash
# Create a new polkit rule file
sudo nano /etc/polkit-1/rules.d/90-udisks2-mount-headless.rules
```

- Add this content to the polkit rule file:

```ini
// Allow users in the 'plugdev' group to mount hardware devices without authentication
// in headless (non-active console) sessions.
// Change the plugdev group name to what you want.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat") &&
        subject.isInGroup("plugdev"))
    {
        return polkit.Result.YES;
    }
});
```

> [!IMPORTANT]
>
> - polkit.addRule(function(action, subject) { ... });: Defines a new rule.
> - action.id: Refers to the specific udisks2 action being attempted, which gio use behind the scenes to mount a hardware device.
> - subject.isInGroup("plugdev"): Checks if the user (subject) is a member of the plugdev group.
> - polkit.Result.YES: Grants permission without requiring authentication.

- Save the file with `Ctrl+X`, then press `y` and `Enter` to confirm.
- Reload the polkit rules with this command:

  ```bash
  sudo systemctl restart polkit.service
  ```

- Add user to `plugdev`. Then run `newgrp groupname` or log out and log back in.

  ```bash
  sudo usermod -a -G plugdev $(whoami)`
  ```

- Verify the user is in the `plugdev` group.

  ```bash
  groups $(whoami)
  ```

Now you can use gvfs.yazi without any problem.
