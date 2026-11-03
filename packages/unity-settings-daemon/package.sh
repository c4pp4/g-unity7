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

debian_edit() {
	# The sound server of Ubuntu is PipeWire (pipewire-audio conflicts with pulseaudio) #
	sed -i -e "s/^\( *\)pulseaudio\(,\?\)$/\1pipewire-pulse | pulseaudio\2/" debian/control || return 1
	grep -q "^ *pipewire-pulse | pulseaudio,\?$" debian/control || return 1

	# debian/unity-settings-daemon.install moved usr/libexec to usr/lib/unity-settings-daemon, #
	#  the compiled paths kept /usr/libexec (the daemon started by unity-greeter, the localeexec #
	#  script, the fallback mount helper, the backlight, locate pointer and Wacom LED helpers) #
	sed -i -e "s:^CONFIGURE_EXTRA_FLAGS = :&--libexecdir=/usr/lib/unity-settings-daemon :" debian/rules || return 1
	grep -q "^CONFIGURE_EXTRA_FLAGS = --libexecdir=/usr/lib/unity-settings-daemon " debian/rules || return 1
	sed -i -e "s:^usr/libexec/\* /usr/lib/unity-settings-daemon/$:usr/lib/unity-settings-daemon:" \
		debian/unity-settings-daemon.install || return 1
	grep -qx "usr/lib/unity-settings-daemon" debian/unity-settings-daemon.install || return 1
}

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

	# Log out with the dialog of Unity (Ctrl+Alt+Del), not with gnome-session-quit of #
	#  gnome-session (the session manager is cinnamon-session) #
	sed -i \
		-e 's/"gnome-session-quit --logout"/"unity-session-quit --logout"/' \
		plugins/media-keys/gsd-media-keys-manager.c || return 1
	grep -Fq '"unity-session-quit --logout"' plugins/media-keys/gsd-media-keys-manager.c || return 1

	# Apply the regional formats setting also when started by systemd #
	sed -i \
		-e "s:^ExecStart=/usr/lib/unity-settings-daemon/unity-settings-daemon$:&-localeexec:" \
		debian/user/unity-settings-daemon.service || return 1
	grep -Fqx "ExecStart=/usr/lib/unity-settings-daemon/unity-settings-daemon-localeexec" \
		debian/user/unity-settings-daemon.service || return 1

	# Started by the systemd user unit when cinnamon-session runs as a systemd service #
	echo "X-GNOME-HiddenUnderSystemd=true" >> data/unity-settings-daemon.desktop.in.in || return 1
}
