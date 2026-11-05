## Firefox of the Mozilla team PPA (Ubuntu has only the transitional package of
##  the snap) with the Unity global menu of the ehooks.
OVERLAY_PKG="ehooks/www-client/firefox:rapid"
UBUNTU_SRC="firefox"
SOURCE_ARCHIVE="mozillateam/ppa"
GROUP="mozilla"

PATCHES=(
	CUSTOM-unity-menubar.patch
)

debian_edit() {
	local f

	# The pin of g-unity7-apt-pin that keeps this package instead of the package of #
	#  Ubuntu that installs the snap (installed by the choice of g-unity7-cleanup), #
	#  a link and not a conffile: it goes with the package #
	echo "usr/share/g-unity7-apt-pin/firefox.pref etc/apt/preferences.d/g-unity7-firefox.pref" \
		>> debian/firefox.links.in || return 1
	grep -qx "usr/share/g-unity7-apt-pin/firefox.pref etc/apt/preferences.d/g-unity7-firefox.pref" \
		debian/firefox.links.in || return 1
	for f in debian/control.in debian/control; do
		# and GTK with populate-firefox-thunderbird-global-submenus.patch (the #
		#  submenus of the global menu stay empty without it) #
		sed -i -e "/^Package: \(@MOZ_PKG_NAME@\|firefox\)$/,/^$/{s/^\(\t\)\${shlibs:Depends}$/&,\n\1g-unity7-apt-pin (>= 1+gu7.2~),\n\1libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)/}" \
			"${f}" || return 1
		grep -q "^	g-unity7-apt-pin (>= 1+gu7.2~),$" "${f}" || return 1
		grep -q "^	libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)$" "${f}" || return 1
	done
}
