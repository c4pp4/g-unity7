## Own package: the GSettings overrides of unity-base/unity-settings and
##  unity-base/unity-greeter with the default USE flags of the overlay
##  (+accessibility +ubuntu-sounds, -lowgfx, all scopes, +ready-sound).
OVERLAY_PKG="unity-base/unity-settings"
GROUP="desktop"
OVERLAY_FILES=(
	unity-base/unity-greeter/files/ubuntu-unity-greeter.gsettings-override
)

local_prepare() {
	local unity=90_g-unity7.gschema.override greeter=90_g-unity7-greeter.gschema.override

	cp "${FILESDIR}"/ubuntu-unity.gsettings-override "${unity}" || return 1
	cp "${OVERLAY_DIR}"/unity-base/unity-greeter/files/ubuntu-unity-greeter.gsettings-override "${greeter}" || return 1

	# +ready-sound: the greeter plays its ready sound #
	sed -i -e "/play-ready-sound/d" "${greeter}" || return 1
	! grep -Fq "play-ready-sound" "${greeter}" || return 1

	# The G Unity⁷ logo of unity-greeter, 20_ubuntu-unity.gschema.override of #
	#  ubuntu-unity-settings sets the Ubuntu Unity logo #
	sed -i \
		-e "/^\[com.canonical.unity-greeter:unity-greeter\]$/a logo = '/usr/share/unity-greeter/logo.png'" \
		"${greeter}" || return 1
	grep -qx "logo = '/usr/share/unity-greeter/logo.png'" "${greeter}" || return 1
}
