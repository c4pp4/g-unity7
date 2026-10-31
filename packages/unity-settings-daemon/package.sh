OVERLAY_PKG="unity-base/unity-settings-daemon"
UBUNTU_SRC="unity-settings-daemon"
GROUP="desktop"

## The default USE flags of the ebuild: +colord +input_devices_wacom
##  +short-touchpad-timeout (optional-colord-and-wacom.patch is not needed).
PATCHES=(
	do-not-close-osd-notifications-on-stop.patch
	fix-volume-queue-use-after-free.patch
	remove-nautilus-support.patch
	rename-mutter-dbus-interface-to-muffin.patch
	shortcut-alt-app.patch
)

src_edit() {
	# https://bugzilla.gnome.org/show_bug.cgi?id=621836
	sed -i \
		-e "/g_ptr_array_add/{s/1.0/0.5/}" \
		plugins/mouse/gsd-mouse-manager.c || return 1
	grep -Fq 'g_ptr_array_add (args, "0.5");' plugins/mouse/gsd-mouse-manager.c || return 1

	# Don't let the forked GL texture size helper fall through on execve failure #
	sed -i \
		-e "s/execve (canary_argv\[0\], canary_argv, canary_env);/& _exit (1);/" \
		gnome-settings-daemon/gsd-rr-config.c || return 1
	grep -Fq "execve (canary_argv[0], canary_argv, canary_env); _exit (1);" gnome-settings-daemon/gsd-rr-config.c || return 1

	# Apply the regional formats setting also when started by systemd #
	sed -i \
		-e "s:^ExecStart=/usr/lib/unity-settings-daemon/unity-settings-daemon$:&-localeexec:" \
		debian/user/unity-settings-daemon.service || return 1
	grep -Fqx "ExecStart=/usr/lib/unity-settings-daemon/unity-settings-daemon-localeexec" \
		debian/user/unity-settings-daemon.service || return 1

	# Started by the systemd user unit when cinnamon-session runs as a systemd service #
	echo "X-GNOME-HiddenUnderSystemd=true" >> data/unity-settings-daemon.desktop.in.in || return 1
}
