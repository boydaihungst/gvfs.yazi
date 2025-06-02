# Headless Workaround to start D-bus session

<!--toc:start-->

- [Headless Workaround to start D-bus session](#headless-workaround-to-start-d-bus-session)
<!--toc:end-->

> [!IMPORTANT]
>
> - Only apply this workaround if you see this error: `GVFS.yazi can only run on DBUS session`.
> - This is a workaround for headless sessions, like connect to a computer via SSH, etc.
> - This only works for systemd users. Most mainstream distros use systemd by default.
> - You only need to do this once, and then you can use gvfs.yazi without any problem.
> - Mount a hardware device (Hard disk, MTP, GPhoto2, etc.) may encounter permission denied error.

Step 1: Connect to the target computer.

Step 2: Run this command in the target computer terminal:

```bash
# Start systemd user session if not already running
sudo loginctl enable-linger $(whoami)
```

Step 3: Reboot.

Now you can use gvfs.yazi without any problem.
