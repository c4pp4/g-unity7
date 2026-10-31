## Own package: the GSettings overrides of unity-base/unity-settings and
##  unity-base/unity-greeter with the default USE flags of the overlay
##  (+accessibility +ubuntu-sounds, -lowgfx, all scopes, +ready-sound), the
##  default wallpaper of Ubuntu and the Yaru icons with the default accent.
OVERLAY_PKG="unity-base/unity-settings"
OVERLAY_FILES=(
	unity-base/unity-greeter/files/ubuntu-unity-greeter.gsettings-override
)

local_prepare() {
	local unity=90_g-unity7.gschema.override greeter=90_g-unity7-greeter.gschema.override
	local wallpaper=/usr/share/backgrounds/warty-final-ubuntu.png

	cp "${FILESDIR}"/ubuntu-unity.gsettings-override "${unity}" || return 1
	cp "${OVERLAY_DIR}"/unity-base/unity-greeter/files/ubuntu-unity-greeter.gsettings-override "${greeter}" || return 1

	# Default wallpaper of Ubuntu instead of Ubuntu Unity #
	sed -i -e "s:^picture-uri = .*:picture-uri = 'file\://${wallpaper}':" "${unity}" || return 1
	grep -Fqx "picture-uri = 'file://${wallpaper}'" "${unity}" || return 1
	sed -i \
		-e "s:^background = .*:background = '${wallpaper}':" \
		-e "/^background-color = /d" \
		"${greeter}" || return 1
	grep -Fqx "background = '${wallpaper}'" "${greeter}" || return 1
	! grep -q "^background-color = " "${greeter}" || return 1

	# Yaru icons with the default accent #
	sed -i -e "s/'Yaru-purple-dark'/'Yaru-dark'/" "${unity}" "${greeter}" || return 1
	! grep -Fq "Yaru-purple" "${unity}" "${greeter}" || return 1

	# +ready-sound: the greeter plays its ready sound #
	sed -i -e "/play-ready-sound/d" "${greeter}" || return 1
	! grep -Fq "play-ready-sound" "${greeter}" || return 1
}
