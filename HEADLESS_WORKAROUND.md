# Headless Workaround to start D-bus session

> [!IMPORTANT]

- Only apply this workaround if you see this error: `GVFS.yazi can only run on DBUS session`.
- This is a workaround for headless sessions, like connect to a computer via SSH, etc.
- This only works for systemd users. Most mainstream distros use systemd by default.
- You only need to do this once, and then you can use gvfs.yazi without any problem.
- Mount a hardware device (Hard disk, MTP, GPhoto2, etc.) may encounter permission denied error.

Step 1: Connect to the target computer
Step 2: Run these commands in its terminal:

```bash
# Start systemd user session if not already running
sudo loginctl enable-linger $(whoami)
```

Now you can use gvfs.yazi without any problem.
