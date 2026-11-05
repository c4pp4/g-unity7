OVERLAY_PKG="unity-base/unity-session"
UBUNTU_SRC="unity-session"
GROUP="desktop"

PATCHES=(
	release-sound-card-at-session-end.patch
)

debian_edit() {
	local f

	# HiddenUnderSystemd and the session fixes of the G Unity⁷ cinnamon-session #
	sed -i -e "s/^\( *\)cinnamon-session,$/\1cinnamon-session (>= 6.6.4-1+gu7),/" debian/control || return 1
	grep -q "^ *cinnamon-session (>= 6.6.4-1+gu7),$" debian/control || return 1

	# Files of the ebuild, installed from debian/g-unity7 #
	install -d debian/g-unity7 || return 1
	install -m 755 "${FILESDIR}"/unity-session-quit debian/g-unity7/ || return 1
	install -m 644 "${FILESDIR}"/unity-portals.conf debian/g-unity7/ || return 1
	install -m 644 "${FILESDIR}"/defaults.list debian/g-unity7/unity-mimeapps.list || return 1
	cat >> debian/unity-session.install <<-EOT || return 1
		debian/g-unity7/unity-session-quit usr/bin/
		debian/g-unity7/unity-portals.conf usr/share/xdg-desktop-portal/
		debian/g-unity7/unity-mimeapps.list usr/share/applications/
	EOT
	for f in unity-session-quit unity-portals.conf unity-mimeapps.list; do
		grep -Fq "debian/g-unity7/${f} " debian/unity-session.install || return 1
	done

	# Default applications of g-unity7-desktop: atril | papers | evince, #
	#  vlc | showtime, the Firefox and Thunderbird debs of G Unity⁷ before their #
	#  snaps, the Chromium snap #
	sed -i \
		-e "s/org\.gnome\.Evince\.desktop;atril\.desktop;org\.gnome\.Papers\.desktop;/atril.desktop;org.gnome.Papers.desktop;org.gnome.Evince.desktop;/" \
		-e "s/org\.gnome\.Evince\.desktop;atril\.desktop;/atril.desktop;org.gnome.Evince.desktop;/" \
		-e "s/org\.gnome\.Evince\.desktop;org\.gnome\.Papers\.desktop;/org.gnome.Papers.desktop;org.gnome.Evince.desktop;/" \
		-e "/^video\/\(x-ms-wmx\|x-totem-stream\)=/!{/^video\//s/vlc\.desktop;/&org.gnome.Showtime.desktop;/}" \
		-e "s/firefox\.desktop;/&firefox_firefox.desktop;/" \
		-e "s/chromium-browser-chromium\.desktop;/chromium_chromium.desktop;chromium-browser.desktop;&/" \
		-e "s/thunderbird\.desktop;/&thunderbird_thunderbird.desktop;/" \
		debian/g-unity7/unity-mimeapps.list || return 1
	grep -qx "application/pdf=atril.desktop;org.gnome.Papers.desktop;org.gnome.Evince.desktop;" debian/g-unity7/unity-mimeapps.list || return 1
	grep -qx "application/x-dvi=atril.desktop;org.gnome.Evince.desktop;" debian/g-unity7/unity-mimeapps.list || return 1
	grep -qx "application/x-ext-pdf=org.gnome.Papers.desktop;org.gnome.Evince.desktop;" debian/g-unity7/unity-mimeapps.list || return 1
	! grep -q "Evince\.desktop;\(atril\|org\.gnome\.Papers\)\.desktop;" debian/g-unity7/unity-mimeapps.list || return 1
	grep -qx "video/mp4=vlc.desktop;org.gnome.Showtime.desktop;org.gnome.Totem.desktop;" debian/g-unity7/unity-mimeapps.list || return 1
	grep -q "^text/html=firefox\.desktop;firefox_firefox\.desktop;.*;chromium_chromium\.desktop;chromium-browser\.desktop;chromium-browser-chromium\.desktop;" debian/g-unity7/unity-mimeapps.list || return 1
	grep -q "^x-scheme-handler/mailto=thunderbird\.desktop;thunderbird_thunderbird\.desktop;" debian/g-unity7/unity-mimeapps.list || return 1

	# GTK_MODULES of the X session with appmenu-gtk-module, as the xinitrc.d script #
	#  of x11-misc/appmenu-gtk-module (unity-gtk-module.service is not used) #
	install -m 644 "${PKG_DIR}"/85unity-session_appmenu-gtk-module debian/g-unity7/ || return 1
	echo "debian/g-unity7/85unity-session_appmenu-gtk-module etc/X11/Xsession.d/" >> debian/unity-session.install || return 1
	grep -Fqx "debian/g-unity7/85unity-session_appmenu-gtk-module etc/X11/Xsession.d/" debian/unity-session.install || return 1
	sed -i -e "s/^\( *\)cinnamon-session (>= 6.6.4-1+gu7),$/\1appmenu-gtk3-module,\n&/" debian/control || return 1
	grep -q "^ *appmenu-gtk3-module,$" debian/control || return 1

	# The accessibility bus of the session instead of the one left by the greeter, #
	#  as 99unity-session of unity-base/unity #
	install -m 644 "${PKG_DIR}"/99unity-session_a11y-bus debian/g-unity7/ || return 1
	echo "debian/g-unity7/99unity-session_a11y-bus etc/X11/Xsession.d/" >> debian/unity-session.install || return 1
	grep -Fqx "debian/g-unity7/99unity-session_a11y-bus etc/X11/Xsession.d/" debian/unity-session.install || return 1
}

src_edit() {
	# Autostart nemo-desktop to manage Unity7 desktop and icons #
	sed -i "/NoDisplay/{s/false/true/}" nemo-unity-autostart.desktop || return 1
	grep -qx "NoDisplay=true" nemo-unity-autostart.desktop || return 1

	# xdg .desktop autostart is managed via cinnamon-session #
	sed -i "/xdg/d" unity-session.target || return 1
	! grep -Fq "xdg-desktop-autostart.target" unity-session.target || return 1

	sed -i "/DesktopName/{s/:ubuntu//}" unity.session || return 1
	grep -qx "DesktopName=Unity:Unity7" unity.session || return 1

	sed -i "/DesktopNames/{s/ubuntu;//}" unity.desktop || return 1
	grep -qx "DesktopNames=Unity;Unity7;" unity.desktop || return 1
}
