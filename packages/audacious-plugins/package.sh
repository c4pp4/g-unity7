OVERLAY_PKG="ehooks/media-plugins/audacious-plugins"
UBUNTU_SRC="audacious-plugins"

## unity-shortcuts-plugin.patch is the variant of packages/audacious-plugins/patches
##  for audacious-plugins 4.5 (the patch of the overlay is for 4.6).
PATCHES=(
	unity-shortcuts-plugin.patch
)

debian_edit() {
	# The Unity Shortcuts plugin (unity-shortcuts-plugin.patch) #
	sed -i -e "s/^ libcurl4-gnutls-dev,$/&\n libdbus-glib-1-dev,/" debian/control || return 1
	grep -qx " libdbus-glib-1-dev," debian/control || return 1
}

src_edit() {
	## Status Icon Plugin first run defaults ##
	sed -i \
		-e "/constexpr StatusIcon/{s/false/true/}" \
		-e "/close_to_tray/{s/FALSE/TRUE/}" \
		src/statusicon/statusicon.cc || return 1
	grep -Fq "constexpr StatusIcon () : GeneralPlugin (info, true)" src/statusicon/statusicon.cc || return 1
	grep -Fq '"close_to_tray", "TRUE"' src/statusicon/statusicon.cc || return 1

	## Desktop Notifications Plugin first run defaults ##
	sed -i \
		-e "/constexpr NotifyPlugin/{s/false/true/}" \
		-e "/actions/{s/TRUE/FALSE/}" \
		src/notify/notify.cc || return 1
	grep -Fq "constexpr NotifyPlugin () : GeneralPlugin (info, true)" src/notify/notify.cc || return 1
	grep -Fq '"actions", "FALSE"' src/notify/notify.cc || return 1
}
