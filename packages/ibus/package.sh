OVERLAY_PKG="ehooks/app-i18n/ibus"
UBUNTU_SRC="ibus"

# Ubuntu already applies ubuntu-forward-panel-properties.patch #
PATCHES=(
	gtk4-check-for-missing-surface.patch
)
