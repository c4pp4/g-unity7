## Firefox from Debian sid with the Unity global menu from the ehooks. Ubuntu
##  only has a transitional package that installs the snap.
OVERLAY_PKG="ehooks/www-client/firefox:rapid"
UBUNTU_SRC="firefox"
DEBIAN_SUITE="sid"
GROUP="mozilla"

# no-exceptions.patch is in patches/, from the Firefox snap: the libc++ of #
#  Ubuntu for wasm32 breaks the RLBox sandboxes #
PATCHES=(
	unity-menubar.patch
	no-exceptions.patch
)

debian_edit() {
	# Build with the NSS of the Firefox source, as the Mozilla Team PPA and #
	#  Debian for trixie do: Debian sid needs a newer system NSS than Ubuntu has #
	sed -i -e "s/^SYSTEM_LIBS += nss$/# &/" debian/rules || return 1
	grep -qx "# SYSTEM_LIBS += nss" debian/rules || return 1
	sed -i -e "/^ *libnss3\(-dev\)\? (>= 2:[0-9.]*~),\?$/d" debian/control || return 1
	! grep -q "libnss3" debian/control || return 1

	# Require g-unity7-apt-pin with the pin file, and GTK with #
	#  populate-firefox-thunderbird-global-submenus.patch. Without it, the #
	#  global menu's submenus stay empty. debian/rules makes debian/control #
	#  again from debian/control.in #
	local f
	for f in debian/control.in debian/control; do
		sed -i -e "s/^\( *\)debianutils (>= 1\.16),$/&\n\1g-unity7-apt-pin (>= 1+gu7.2~),\n\1libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7),/" \
			"${f}" || return 1
		grep -q "^ *g-unity7-apt-pin (>= 1+gu7.2~),$" "${f}" || return 1
		grep -q "^ *libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7),$" "${f}" || return 1
	done

	# Link the g-unity7-apt-pin pin that keeps this package instead of the Ubuntu #
	#  package that installs the snap. g-unity7-cleanup installs this package when #
	#  the user chooses it. A link is not a conffile, so it goes with the package #
	echo "/usr/share/g-unity7-apt-pin/firefox.pref /etc/apt/preferences.d/g-unity7-firefox.pref" \
		>> debian/browser.links.in || return 1
	grep -qx "/usr/share/g-unity7-apt-pin/firefox.pref /etc/apt/preferences.d/g-unity7-firefox.pref" \
		debian/browser.links.in || return 1

	# The launcher of the ehooks, with the quicklist and more translations. Keep #
	#  the window class of the Debian build #
	cp "${FILESDIR}"/firefox.desktop debian/browser.desktop.in || return 1
	sed -i -e "s/^StartupWMClass=.*/StartupWMClass=@MOZ_APP_REMOTINGNAME@/" debian/browser.desktop.in || return 1
	grep -qx "StartupWMClass=@MOZ_APP_REMOTINGNAME@" debian/browser.desktop.in || return 1
}
