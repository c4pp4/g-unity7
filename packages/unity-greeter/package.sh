OVERLAY_PKG="unity-base/unity-greeter"
UBUNTU_SRC="unity-greeter"
GROUP="desktop"

## envvars-pipewire-indicators.patch in packages/unity-greeter/patches is a
##  variant with only the environment variables, because the greeter always
##  runs with systemd on Ubuntu.
PATCHES=(
	envvars-pipewire-indicators.patch
	fix-prompt-box-resize.patch
	quit-unity-greeter-immediately-on-active-session-login.patch
	start-notify-osd.patch
	rename-ubuntu-session-to-unity.diff
)

debian_edit() {
	# start-notify-osd.patch starts notify-osd, which has no D-Bus activation in Ubuntu #
	sed -i -e "s/^\( *\)network-manager-gnome,$/&\n\1notify-osd,/" debian/control || return 1
	grep -q "^ *notify-osd,$" debian/control || return 1

	# liblightdm-gobject-dev provides liblightdm-gobject-1-dev only without a #
	#  version, and the liblightdm-gobject-1 Vala API is in lightdm-vala #
	sed -i -e "s/^\( *\)liblightdm-gobject-1-dev (>= 1.4.0),$/\1liblightdm-gobject-dev (>= 1.4.0),\n\1lightdm-vala,/" debian/control || return 1
	grep -q "^ *liblightdm-gobject-dev (>= 1.4.0),$" debian/control || return 1
	grep -q "^ *lightdm-vala,$" debian/control || return 1

	# 60-lightdm-gtk-greeter.conf from lightdm-gtk-greeter, which Ubuntu Unity #
	#  installs, overrides 50-unity-greeter.conf, so use a later file #
	mv debian/50-unity-greeter.conf debian/90-unity-greeter.conf || return 1
	sed -i -e "s:^debian/50-unity-greeter.conf :debian/90-unity-greeter.conf :" debian/install || return 1
	grep -q "^debian/90-unity-greeter.conf " debian/install || return 1

	# G Unity⁷ logo, and hide the logo on secondary monitors #
	install -d debian/g-unity7 || return 1
	install -m 644 "${BRANDING_DIR}"/greeter-logo.png debian/g-unity7/logo.png || return 1
	install -m 644 "${FILESDIR}"/branding/empty_cof.png debian/g-unity7/cof.png || return 1
	printf '\n%s\n\t%s\n' \
		"execute_after_dh_install:" \
		"install -m 644 debian/g-unity7/logo.png debian/g-unity7/cof.png debian/unity-greeter/usr/share/unity-greeter/" \
		>> debian/rules || return 1
	grep -Pq "^\tinstall -m 644 debian/g-unity7/logo.png " debian/rules || return 1
}

src_edit() {
	# unity-settings-daemon is installed to /usr/lib/unity-settings-daemon, but the #
	#  binary variable in Ubuntu's unity-settings-daemon.pc is /usr/libexec. The #
	#  greeter waited for the xsettings plugin of a daemon that never started and #
	#  stayed black. Use a fixed path instead of depending on the #
	#  unity-settings-daemon-dev version that the greeter is built with #
	sed -i \
		-e "s:^USD_BINARY=\`\$PKG_CONFIG --variable=binary unity-settings-daemon\`$:USD_BINARY=/usr/lib/unity-settings-daemon/unity-settings-daemon:" \
		configure.ac || return 1
	grep -qx "USD_BINARY=/usr/lib/unity-settings-daemon/unity-settings-daemon" configure.ac || return 1

	# Panel icon size and padding #
	sed -i \
		-e "/entry.image.show.connect/i entry.image.set_pixel_size(22);" \
		-e "/hbox.pack_start (entry.image/{s/0/3/}" \
		src/menubar.vala || return 1
	grep -Fqx "entry.image.set_pixel_size(22);" src/menubar.vala || return 1
	grep -Fq "hbox.pack_start (entry.image, false, false, 3);" src/menubar.vala || return 1
}
