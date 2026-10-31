OVERLAY_PKG="ehooks/gnome-extra/cinnamon-session"
UBUNTU_SRC="cinnamon-session"
GROUP="session"

PATCHES=(
	Add-SessionIsActive-property-and-fix-session-handling.patch
	Support-X-GNOME-HiddenUnderSystemd.patch
	unity-session-properties-application.patch
	Use-the-default-mechanism-to-check-XDG_CURRENT_DESKTOP.patch
	enable-nm-applet-autostart.diff
)

debian_edit() {
	local f

	# unity-session-properties added by unity-session-properties-application.patch #
	cat >> debian/cinnamon-session.install <<-EOT || return 1
		usr/bin/unity-session-properties
		usr/share/applications/unity-session-properties.desktop
		usr/share/man/*/unity-session-properties*
	EOT
	for f in usr/bin/unity-session-properties usr/share/applications/unity-session-properties.desktop; do
		grep -Fqx "${f}" debian/cinnamon-session.install || return 1
	done
}
