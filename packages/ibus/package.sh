OVERLAY_PKG="ehooks/app-i18n/ibus"
UBUNTU_SRC="ibus"

# Ubuntu already applies ubuntu-forward-panel-properties.patch. The ehooks' #
#  --daemonize in org.freedesktop.IBus.service is for Gentoo, where the #
#  D-Bus activated daemon exits at once. Ubuntu starts IBus with im-config #
PATCHES=(
	gtk4-check-for-missing-surface.patch
)
