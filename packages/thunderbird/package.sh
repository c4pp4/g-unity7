## Thunderbird from the Mozilla Team PPA with the Unity global menu from the
##  ehooks. Ubuntu only has a transitional package that installs the snap.
##  The Mozilla Team PPA has the previous ESR, so patches/unity-menubar.patch is
##  the overlay's last patch for it with the later changes of the overlay's ESR
##  patch. Rebase it again when the Mozilla Team PPA moves to the next ESR, or
##  drop it if the ESR patch of the overlay applies.
##  thunderbird.desktop from the ehooks is not needed: the Mozilla Team file has
##  the same actions and translations and differs only in StartupWMClass.
OVERLAY_PKG="ehooks/mail-client/thunderbird-153"
UBUNTU_SRC="thunderbird"
SOURCE_ARCHIVE="mozillateam/ppa"
GROUP="mozilla"

PATCHES=(
	unity-menubar.patch
)

debian_edit() {
	local f

	# Use the window manager's title bar instead of drawing the tabs in it, as #
	#  the ehooks do in gentoo-prefs.js. vendor.js holds the package defaults, #
	#  syspref.js in /etc is left to the administrator #
	echo -e '\n// G Unity⁷: use the window title bar instead of drawing the tabs in it\npref("mail.tabs.drawInTitlebar", false);' \
		>> debian/vendor.js || return 1
	grep -Fqx 'pref("mail.tabs.drawInTitlebar", false);' debian/vendor.js || return 1

	# Link the g-unity7-apt-pin pin that keeps this package instead of the Ubuntu #
	#  package that installs the snap. g-unity7-cleanup installs this package when #
	#  the user chooses it. A link is not a conffile, so it goes with the package #
	echo "usr/share/g-unity7-apt-pin/thunderbird.pref etc/apt/preferences.d/g-unity7-thunderbird.pref" \
		>> debian/thunderbird.links.in || return 1
	grep -qx "usr/share/g-unity7-apt-pin/thunderbird.pref etc/apt/preferences.d/g-unity7-thunderbird.pref" \
		debian/thunderbird.links.in || return 1

	# Build with rustc 1.95 of Ubuntu 26.10. The Mozilla Team PPA builds the ESR #
	#  only in noble with rustc 1.85 and copies the binaries to the newer series. #
	#  Debian unstable built Thunderbird 140.14 with rustc 1.95 and clang 21 #
	sed -i -e "s/^RUSTC_VERSIONS = 1\.85 /RUSTC_VERSIONS = 1.95 1.85 /" debian/build/rules.mk || return 1
	grep -qx "RUSTC_VERSIONS = 1.95 1.85 1.84 1.82" debian/build/rules.mk || return 1
	for f in debian/control.in debian/control; do
		sed -i \
			-e "s/^\(\t\)cargo-1\.85 | /\1cargo-1.95 | cargo-1.85 | /" \
			-e "s/^\(\t\)rustc-1\.85 | /\1rustc-1.95 | rustc-1.85 | /" \
			"${f}" || return 1
		grep -qx "	cargo-1.95 | cargo-1.85 | cargo-1.84 | cargo-1.82," "${f}" || return 1
		grep -qx "	rustc-1.95 | rustc-1.85 | rustc-1.84 | rustc-1.82," "${f}" || return 1
	done

	for f in debian/control.in debian/control; do
		# Require g-unity7-apt-pin with the pin file, and GTK with #
		#  populate-firefox-thunderbird-global-submenus.patch. Without it, the #
		#  global menu's submenus stay empty #
		sed -i -e "/^Package: \(@MOZ_PKG_NAME@\|thunderbird\)$/,/^$/{s/^\(\t\)\${misc:Depends}$/&,\n\1g-unity7-apt-pin (>= 1+gu7.2~),\n\1libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)/}" \
			"${f}" || return 1
		grep -q "^	g-unity7-apt-pin (>= 1+gu7.2~),$" "${f}" || return 1
		grep -q "^	libgtk-3-0t64 (>= 3.24.52-0ubuntu1+gu7)$" "${f}" || return 1
	done
}
