OVERLAY_PKG="unity-indicators/indicator-sound"
UBUNTU_SRC="indicator-sound"
GROUP="desktop"

PATCHES=(
	connect-to-playlists-proxy.patch
	exit-without-finalizing-on-sigterm.patch
	fix-notification-icon.patch
	forget-uninstalled-players.patch
	greeter-user-lookup-on-name-owner.patch
	implement-greeter-player-controls.patch
	quiet-missing-pulseaudio-dbus.patch
	remove-playlist-item-only-if-present.patch
)

src_edit() {
	# Do not delay logout by 90 s if the service hangs on termination #
	sed -i "/^Restart=/a TimeoutStopSec=10" data/indicator-sound.service.in || return 1
	grep -qx "TimeoutStopSec=10" data/indicator-sound.service.in || return 1
}
