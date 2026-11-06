OVERLAY_PKG="ehooks/x11-libs/gtk+:3"
UBUNTU_SRC="gtk+3.0"
GROUP="mozilla"

## Only populate-firefox-thunderbird-global-submenus.patch. Ubuntu already has
##  the other patches from the ehooks series.
PATCHES=(
	populate-firefox-thunderbird-global-submenus.patch
)
