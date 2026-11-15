OVERLAY_PKG="ehooks/x11-libs/gtk+:3"
UBUNTU_SRC="gtk+3.0"
GROUP="mozilla"

## Only the own patches. Ubuntu already has the other patches from the ehooks
##  series.
PATCHES=(
	populate-firefox-thunderbird-global-submenus.patch
	read-net-supported-again-for-unity-border-radius.patch
)
