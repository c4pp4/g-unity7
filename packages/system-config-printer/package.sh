OVERLAY_PKG="ehooks/app-admin/system-config-printer"
UBUNTU_SRC="system-config-printer"
GROUP="desktop"

## The print applet is hidden in Unity by the Ubuntu patchset already.

src_edit() {
	local f=system-config-printer.desktop.in

	# autopoint of gettext 1.0 takes AX_REQUIRE_DEFINED([AM_GNU_GETTEXT]) for an #
	#  AM_GNU_GETTEXT without 'external' and stops (dh_autoreconf failed) #
	sed -i -e "/^AX_REQUIRE_DEFINED(\[AM_GNU_GETTEXT\])$/d" configure.ac || return 1
	! grep -Fq "AX_REQUIRE_DEFINED([AM_GNU_GETTEXT])" configure.ac || return 1
	# gettext 1.0 has no gettext.m4 in /usr/share/aclocal, autopoint copies it to m4 #
	sed -i -e "s/^aclocal$/aclocal -I m4/" bootstrap || return 1
	grep -qx "aclocal -I m4" bootstrap || return 1

	# The Printers panel of unity-control-center (printers-fix_launcher.patch) is shown instead #
	if grep -q "^NotShowIn=" "${f}"; then
		sed -i -e "s/^NotShowIn=\(.*\)$/NotShowIn=\1Unity;/" "${f}" || return 1
	else
		echo "NotShowIn=Unity;" >> "${f}" || return 1
	fi
	grep -q "^NotShowIn=.*Unity;$" "${f}" || return 1

	# Show the printers icon as the About dialog logo #
	# 'printer' resolves to printer-symbolic of ubuntu-mono-* and Yaru-*-dark #
	sed -i \
		-e "s:\(self.AboutDialog.set_\)\(icon_name('printer\):\1logo_\2s:" \
		system-config-printer.py || return 1
	grep -q "self.AboutDialog.set_logo_icon_name('printers')" system-config-printer.py || return 1
}
