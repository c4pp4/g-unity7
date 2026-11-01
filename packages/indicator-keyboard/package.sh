OVERLAY_PKG="unity-indicators/indicator-keyboard"
UBUNTU_SRC="indicator-keyboard"
GROUP="desktop"

PATCHES=(
	Prevent-segfault-by-obtaining-style-context-associated-to-widget.patch
	Handle-SIGTERM-in-the-main-loop.patch
)
