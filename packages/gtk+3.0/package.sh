OVERLAY_PKG="ehooks/x11-libs/gtk+:3"
UBUNTU_SRC="gtk+3.0"
GROUP="mozilla"

## Only populate-firefox-thunderbird-global-submenus.patch, the other patches
##  of the series of the ehooks are in the patchset of Ubuntu.
PATCHES=(
	populate-firefox-thunderbird-global-submenus.patch
)
