## Own package: the GSettings overrides of unity-base/unity-settings,
##  unity-base/unity-greeter and media-fonts/fonts-ubuntu with the default USE
##  flags of the overlay (+accessibility +ubuntu-sounds, -lowgfx, all scopes,
##  +ready-sound).
OVERLAY_PKG="unity-base/unity-settings"
GROUP="desktop"
OVERLAY_FILES=(
	unity-base/unity-greeter/files/ubuntu-unity-greeter.gsettings-override
	media-fonts/fonts-ubuntu/files/fonts-ubuntu.gsettings-override
)

local_prepare() {
	local unity=90_g-unity7.gschema.override greeter=90_g-unity7-greeter.gschema.override
	local fonts=91_g-unity7-fonts-ubuntu.gschema.override

	cp "${FILESDIR}"/ubuntu-unity.gsettings-override "${unity}" || return 1
	cp "${OVERLAY_DIR}"/unity-base/unity-greeter/files/ubuntu-unity-greeter.gsettings-override "${greeter}" || return 1
	# The monospace font size of fonts-ubuntu, after ${unity} as 11_fonts-ubuntu #
	#  after 10_ubuntu-unity in Gentoo #
	cp "${OVERLAY_DIR}"/media-fonts/fonts-ubuntu/files/fonts-ubuntu.gsettings-override "${fonts}" || return 1

	# +ready-sound: the greeter plays its ready sound #
	sed -i -e "/play-ready-sound/d" "${greeter}" || return 1
	! grep -Fq "play-ready-sound" "${greeter}" || return 1

	# The G Unity⁷ logo of unity-greeter and of the lock screen of Unity (it #
	#  reads the greeter settings in the Unity session), 20_ubuntu-unity.gschema.override #
	#  of ubuntu-unity-settings sets the Ubuntu Unity logo #
	sed -i \
		-e "/^\[com.canonical.unity-greeter\]$/a logo = '/usr/share/unity-greeter/logo.png'" \
		"${greeter}" || return 1
	grep -qx "logo = '/usr/share/unity-greeter/logo.png'" "${greeter}" || return 1

	# spice-vdagent is started by its systemd user unit (graphical-session.target.wants #
	#  of Debian), its XDG autostart file has X-systemd-skip, which cinnamon-session #
	#  does not know: the second agent was refused by spice-vdagentd and flooded the #
	#  journal. Added to the autostart-blacklist of the Unity session #
	sed -i \
		-e "/^\[org.cinnamon.SessionManager:Unity\]$/,/^\[/{s/^\(autostart-blacklist = \[.*\)\]$/\1, 'spice-vdagent']/}" \
		"${unity}" || return 1
	grep -q "^autostart-blacklist = \[.*, 'spice-vdagent'\]$" "${unity}" || return 1
}
