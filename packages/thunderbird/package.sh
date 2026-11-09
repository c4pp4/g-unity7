## Thunderbird from Debian experimental with the Unity global menu from the
##  ehooks. Ubuntu only has a transitional package that installs the snap.
##  Debian has the monthly releases, the same as the snap, in experimental and
##  the ESR in sid.
OVERLAY_PKG="ehooks/mail-client/thunderbird"
UBUNTU_SRC="thunderbird"
DEBIAN_SUITE="experimental"
GROUP="mozilla"

PATCHES=(
	unity-menubar.patch
)

debian_edit() {
	local class

	# Build without the -flto=auto that dpkg-buildflags of Ubuntu adds on amd64, #
	#  as Debian does. With it, the link of libxul.so runs an LTO of all the C++ #
	#  code and Launchpad kills the build for inactivity #
	sed -i -e "1a export DEB_BUILD_MAINT_OPTIONS += optimize=-lto" debian/rules || return 1
	grep -qx "export DEB_BUILD_MAINT_OPTIONS += optimize=-lto" debian/rules || return 1

	# Build with the NSS of the Thunderbird source, as the Firefox port does: #
	#  Thunderbird needs a newer system NSS than Ubuntu has. debian/thunderbird.install #
	#  installs the bundled libraries with usr/lib/thunderbird/lib* #
	sed -i -e "s/^ac_add_options --with-system-nss$/ac_add_options --without-system-nss/" \
		debian/mozconfig.default || return 1
	grep -qx "ac_add_options --without-system-nss" debian/mozconfig.default || return 1
	sed -i -e "/^ *libnss3-dev (>= 2:[0-9.]*~),$/d" debian/control || return 1
	! grep -q "libnss3" debian/control || return 1

	# Use the window manager's title bar instead of drawing the tabs in it, as #
	#  the ehooks do in gentoo-prefs.js. vendor.js holds the package defaults, #
	#  thunderbird.js in /etc/thunderbird/pref is left to the administrator #
	echo -e '\n// G Unity⁷: use the window title bar instead of drawing the tabs in it\npref("mail.tabs.drawInTitlebar", false);' \
		>> debian/vendor.js || return 1
	grep -Fqx 'pref("mail.tabs.drawInTitlebar", false);' debian/vendor.js || return 1

	# Require g-unity7-apt-pin with the pin file, and GTK with #
	#  populate-firefox-thunderbird-global-submenus.patch. Without it, the #
	#  global menu's submenus stay empty #
	sed -i -e "/^Package: thunderbird$/,/^$/{s/^ debianutils (>= 1\.16),$/&\n g-unity7-apt-pin (>= 1+gu7.2~),\n libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7),/}" \
		debian/control || return 1
	grep -qx " g-unity7-apt-pin (>= 1+gu7.2~)," debian/control || return 1
	grep -qx " libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)," debian/control || return 1

	# Link the g-unity7-apt-pin pin that keeps this package instead of the Ubuntu #
	#  package that installs the snap. g-unity7-cleanup installs this package when #
	#  the user chooses it. A link is not a conffile, so it goes with the package #
	echo "usr/share/g-unity7-apt-pin/thunderbird.pref etc/apt/preferences.d/g-unity7-thunderbird.pref" \
		>> debian/thunderbird.links || return 1
	grep -qx "usr/share/g-unity7-apt-pin/thunderbird.pref etc/apt/preferences.d/g-unity7-thunderbird.pref" \
		debian/thunderbird.links || return 1

	# The launcher of the ehooks, with more translations of the quicklist. Keep #
	#  the window class of the Debian build (thunderbird-default) #
	class=$(sed -n "s/^StartupWMClass=//p" debian/thunderbird.desktop)
	[[ -n ${class} ]] || return 1
	cp "${FILESDIR}"/thunderbird.desktop debian/thunderbird.desktop || return 1
	sed -i -e "s/^StartupWMClass=.*/StartupWMClass=${class}/" debian/thunderbird.desktop || return 1
	grep -qx "StartupWMClass=${class}" debian/thunderbird.desktop || return 1
}
