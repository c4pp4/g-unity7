## Firefox from the Mozilla Team PPA with the Unity global menu from the
##  ehooks. Ubuntu only has a transitional package that installs the snap.
OVERLAY_PKG="ehooks/www-client/firefox:rapid"
UBUNTU_SRC="firefox"
SOURCE_ARCHIVE="mozillateam/ppa"
GROUP="mozilla"
## Remove when the overlay patch applies to Firefox 160 (dom/xul/moz.build).
HOLD="unity-menubar.patch does not apply to Firefox 160 yet"

PATCHES=(
	unity-menubar.patch
)

debian_edit() {
	local f

	# Link the g-unity7-apt-pin pin that keeps this package instead of the Ubuntu #
	#  package that installs the snap. g-unity7-cleanup installs this package when #
	#  the user chooses it. A link is not a conffile, so it goes with the package #
	echo "usr/share/g-unity7-apt-pin/firefox.pref etc/apt/preferences.d/g-unity7-firefox.pref" \
		>> debian/firefox.links.in || return 1
	grep -qx "usr/share/g-unity7-apt-pin/firefox.pref etc/apt/preferences.d/g-unity7-firefox.pref" \
		debian/firefox.links.in || return 1
	for f in debian/control.in debian/control; do
		# Require g-unity7-apt-pin with the pin file, and GTK with #
		#  populate-firefox-thunderbird-global-submenus.patch. Without it, the #
		#  global menu's submenus stay empty #
		sed -i -e "/^Package: \(@MOZ_PKG_NAME@\|firefox\)$/,/^$/{s/^\(\t\)\${shlibs:Depends}$/&,\n\1g-unity7-apt-pin (>= 1+gu7.2~),\n\1libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)/}" \
			"${f}" || return 1
		grep -q "^	g-unity7-apt-pin (>= 1+gu7.2~),$" "${f}" || return 1
		grep -q "^	libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)$" "${f}" || return 1
	done
}
