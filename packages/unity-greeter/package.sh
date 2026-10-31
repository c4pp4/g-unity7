OVERLAY_PKG="unity-base/unity-greeter"
UBUNTU_SRC="unity-greeter"
GROUP="desktop"

## envvars-pipewire-indicators.patch is the variant of packages/unity-greeter/patches
##  (only the environment variables, the greeter always runs with systemd on
##  Ubuntu). start-notify-osd.patch is not needed, notify-osd is D-Bus activated.
PATCHES=(
	envvars-pipewire-indicators.patch
	fix-prompt-box-resize.patch
	quit-unity-greeter-immediately-on-active-session-login.patch
	rename-ubuntu-session-to-unity.diff
)

debian_edit() {
	# liblightdm-gobject-1-dev is only provided without a version by liblightdm-gobject-dev, #
	#  the Vala API of liblightdm-gobject-1 is in lightdm-vala #
	sed -i -e "s/^\( *\)liblightdm-gobject-1-dev (>= 1.4.0),$/\1liblightdm-gobject-dev (>= 1.4.0),\n\1lightdm-vala,/" debian/control || return 1
	grep -q "^ *liblightdm-gobject-dev (>= 1.4.0),$" debian/control || return 1
	grep -q "^ *lightdm-vala,$" debian/control || return 1

	# G Unity⁷ logo and the hidden logo of secondary monitors #
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
	# Panel icon size and padding #
	sed -i \
		-e "/entry.image.show.connect/i entry.image.set_pixel_size(22);" \
		-e "/hbox.pack_start (entry.image/{s/0/3/}" \
		src/menubar.vala || return 1
	grep -Fqx "entry.image.set_pixel_size(22);" src/menubar.vala || return 1
	grep -Fq "hbox.pack_start (entry.image, false, false, 3);" src/menubar.vala || return 1
}
