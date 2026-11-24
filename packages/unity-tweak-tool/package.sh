OVERLAY_PKG="unity-extra/unity-tweak-tool"
UBUNTU_SRC="unity-tweak-tool"
GROUP="desktop"

## The ebuild's default USE flags (+bluetooth +files +hud), so remove-hud.diff is
##  not needed.
##  xorg-cursor-themes-path.diff is for Gentoo's cursor theme path.
PATCHES=(
	unity-cursor-scale-factor.diff
)

debian_edit() {
	# Use the GSettings cursor theme for X applications in the Unity session #
	#  only, as the other Xsession.d scripts of G Unity⁷ (the one of the ebuild #
	#  runs in every X session) #
	install -d debian/g-unity7 || return 1
	{
		printf '%s\n' '# Use the GSettings cursor theme for X applications in the Unity session' \
			'case :$XDG_CURRENT_DESKTOP: in' '	*:Unity:*)'
		sed -e 's/^/\t\t/' "${FILESDIR}"/95-xcursor-theme
		printf '%s\n' '		;;' 'esac'
	} > debian/g-unity7/95xcursor-theme || return 1
	chmod 644 debian/g-unity7/95xcursor-theme || return 1
	grep -qx "$(printf '\t\t')export XCURSOR_THEME=.*" debian/g-unity7/95xcursor-theme || return 1
	echo "debian/g-unity7/95xcursor-theme etc/X11/Xsession.d/" >> debian/install || return 1
	grep -Fqx "debian/g-unity7/95xcursor-theme etc/X11/Xsession.d/" debian/install || return 1
	prerm_remove_on_downgrade unity-tweak-tool /etc/X11/Xsession.d/95xcursor-theme || return 1
}

src_edit() {
	# Make Unity Tweak Tool appear in unity-control-center #
	sed -i \
		-e 's:Categories=.*:Categories=Settings;X-GNOME-Settings-Panel;X-GNOME-PersonalSettings;X-Unity-Settings-Panel;:' \
		-e 's: %f::' \
		-e '/Actions=/{:a;n;/^$/!ba;i\X-Unity-Settings-Panel=unitytweak' -e '}' \
		unity-tweak-tool.desktop.in || return 1
	grep -qx "X-Unity-Settings-Panel=unitytweak" unity-tweak-tool.desktop.in || return 1
}
