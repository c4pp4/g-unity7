OVERLAY_PKG="unity-base/unity-control-center"
UBUNTU_SRC="unity-control-center"
GROUP="desktop"

## The ebuild's default USE flags (+cups: printers-fix_launcher.patch).
##  01-langselector.patch and 02-optional-bt-colord-kerberos-wacom.patch only
##  replace Ubuntu tools that Gentoo lacks and make dependencies optional.
## network-use-own-translation-domain.patch and
##  sharing-use-own-translation-domain.patch are only in the port: the ebuild
##  merges the translations of these panels into unity-control-center
##  (unity-base/unity-language-pack), which the Ubuntu language packs hide, so
##  g-unity7-l10n installs them in their own domains.
## network-handle-missing-rfkill-plugin.patch is left out: it hides the
##  airplane mode switch when unity-settings-daemon has no rfkill plugin, as
##  with USE=-rfkill in Gentoo, but the unity-settings-daemon of the PPA has it.
PATCHES=(
	appearance-ignore_screenshots_from_mate_screenshot.patch
	appearance-process_filename_dark_files.patch
	appearance-render_static_preview_once.patch
	network-fix-hotspot-button-state.patch
	sharing-fix_translation.patch
	shell-fix_theme_selection_and_hover.patch
	use-cinnamon-schema-for-idle-delay.patch
	printers-fix_launcher.patch
	sharing-support-ssh-socket-activation.patch
	network-use-own-translation-domain.patch
	sharing-use-own-translation-domain.patch
)

debian_edit() {
	local policy

	# The metadata is installed to usr/share/metainfo (Fix metadata path) #
	sed -i -e "s:usr/share/appdata:usr/share/metainfo:" debian/unity-control-center.install || return 1
	grep -Fq "usr/share/metainfo" debian/unity-control-center.install || return 1

	# Without Fcitx 4, as the ebuild (--disable-fcitx). The libraries of Fcitx 4 #
	#  suggest fcitx, which apt then keeps with the KDE Frameworks that it pulls #
	#  in, although G Unity⁷ uses IBus. autogen.sh also runs configure #
	sed -i -e "/^ *fcitx-libs-dev,$/d" debian/control || return 1
	! grep -q "fcitx" debian/control || return 1
	sed -i \
		-e "s/^\(\t\.\/autogen\.sh --disable-onlineaccounts\)$/\1 --disable-fcitx/" \
		-e "s/^\(\t\t\t--disable-onlineaccounts\) /\1 --disable-fcitx /" \
		debian/rules || return 1
	[[ $(grep -Fc -- "--disable-onlineaccounts --disable-fcitx" debian/rules) -eq 2 ]] || return 1

	# The SSH units of Ubuntu: sshd.service is only an alias of ssh.service, and #
	#  ssh.socket starts the server (sharing-support-ssh-socket-activation.patch) #
	sed -i \
		-e '/^export DEB_CFLAGS_MAINT_APPEND = /a export DEB_CPPFLAGS_MAINT_APPEND = -DSSHD_SERVICE=\\"ssh.service\\" -DSSHD_SOCKET=\\"ssh.socket\\"' \
		debian/rules || return 1
	grep -Fqx 'export DEB_CPPFLAGS_MAINT_APPEND = -DSSHD_SERVICE=\"ssh.service\" -DSSHD_SOCKET=\"ssh.socket\"' \
		debian/rules || return 1

	# The remote login helper of the sharing panel, which Ubuntu does not install #
	echo "usr/libexec/ucc-remote-login-helper" >> debian/unity-control-center.install || return 1
	grep -Fqx "usr/libexec/ucc-remote-login-helper" debian/unity-control-center.install || return 1

	# dh_translations adds gettext-domain="unity-control-center" also to the #
	#  messages of the remote login policy, which have the domain of the sharing #
	#  panel (sharing-use-own-translation-domain.patch): drop the duplicate #
	policy=debian/unity-control-center/usr/share/polkit-1/actions/com.canonical.controlcenter.remote-login-helper.policy
	rules_add_target execute_after_dh_translations \
		"sed -i -e 's/ gettext-domain=\"unity-control-center\"//' \\" \
		$'\t'"${policy}" \
		"! grep -Fq 'gettext-domain=\"unity-control-center\"' \\" \
		$'\t'"${policy}" \
		"[ \$\$(grep -Fc 'gettext-domain=\"unity-control-center-sharing\"' \\" \
		$'\t'"${policy}) -eq 2 ]" || return 1

	# The services of the sharing panel, which the ebuild depends on with its #
	#  default sharing USE flag. gnome-user-share and rygel start only when #
	#  they are enabled in the panel, but openssh-server starts the SSH server #
	#  at once, so it is only suggested. The panel shows only installed services #
	sed -i \
		-e "/^Package: unity-control-center$/,/^$/{s/^\( *\)ubuntu-system-service$/\1ubuntu-system-service,\n\1gnome-user-share,\n\1rygel/}" \
		-e "/^Package: unity-control-center$/,/^$/{s/^\( *\)x11-xserver-utils$/\1x11-xserver-utils,\n\1openssh-server/}" \
		debian/control || return 1
	sed -n "/^Package: unity-control-center$/,/^$/p" debian/control \
		| grep -A 2 -x " *ubuntu-system-service," | grep -qx " *rygel" || return 1
	sed -n "/^Package: unity-control-center$/,/^$/p" debian/control \
		| grep -A 1 -x " *x11-xserver-utils," | grep -qx " *openssh-server" || return 1
}

src_edit() {
	# Rename cc-remote-login-helper as the ebuild does, because #
	#  gnome-base/gnome-control-center provides it there #
	sed -i \
		-e "s/cc-remote-login-helper/ucc-remote-login-helper/g" \
		panels/sharing/{cc-remote-login.c,com.canonical.controlcenter.remote-login-helper.policy.in.in,Makefile.am} || return 1
	grep -Fq "ucc-remote-login-helper" panels/sharing/cc-remote-login.c || return 1
	grep -Fq "ucc-remote-login-helper" panels/sharing/com.canonical.controlcenter.remote-login-helper.policy.in.in || return 1
	sed -i \
		-e "s/cc_remote_login_helper/ucc_remote_login_helper/g" \
		panels/sharing/Makefile.am || return 1
	grep -Fq "ucc_remote_login_helper_SOURCES = ucc-remote-login-helper.c" panels/sharing/Makefile.am || return 1
	mv panels/sharing/cc-remote-login-helper.c panels/sharing/ucc-remote-login-helper.c || return 1

	# Branding #
	cp "${FILESDIR}"/branding/UnityLogo.svg panels/info/GnomeLogoVerticalMedium.svg || return 1
	sed -i \
		-e 's/"distributor"/"release"/' \
		-e "s/%s.%s.%s/%s.%s.%s (%s)/" \
		-e "/%s.%s.%s/{s/micro/micro, data->distributor/}" \
		-e "/gtk_widget_hide (WID (\"version_label\")/d" \
		-e "s:gnome/gnome:unity/unity:" \
		panels/info/cc-info-panel.c || return 1
	grep -Fq 'g_str_equal (element_name, "release")' panels/info/cc-info-panel.c || return 1
	grep -Fq '"%s.%s.%s (%s)", data->major, data->minor, data->micro, data->distributor' panels/info/cc-info-panel.c || return 1
	grep -Fq 'DATADIR "/unity/unity-version.xml"' panels/info/cc-info-panel.c || return 1
	! grep -Fq 'gtk_widget_hide (WID ("version_label"))' panels/info/cc-info-panel.c || return 1
	sed -i \
		-e "s/UnityLogo.png/GnomeLogoVerticalMedium.svg/" \
		panels/info/info.ui || return 1
	grep -Fq ">GnomeLogoVerticalMedium.svg<" panels/info/info.ui || return 1

	# Fix hostname transliteration #
	sed -i \
		-e "/g_convert/,+6 d" \
		-e "s:ASCII \*/:ASCII */\n\tresult = g_str_to_ascii (pretty, NULL);:" \
		panels/info/hostname-helper.c || return 1
	grep -Fq "translit: '%s'" panels/info/hostname-helper.c || return 1

	# Rename button to be translated #
	sed -i \
		-e "s/_Add Profile…/Add profile/" \
		panels/network/network-ethernet.ui || return 1
	grep -Fq 'translatable="yes">Add profile<' panels/network/network-ethernet.ui || return 1

	# Fix typo (Sha ring) #
	sed -i \
		-e "/Name=/{s/Sha­ring/Sharing/}" \
		panels/sharing/unity-sharing-panel.desktop.in.in || return 1
	grep -qx "_Name=Sharing" panels/sharing/unity-sharing-panel.desktop.in.in || return 1

	# Install only the online-accounts icons for the gnome-online-accounts-gtk #
	#  launcher. debian/rules disables the online-accounts panel #
	sed -i \
		-e "/^if BUILD_ONLINE_ACCOUNTS$/i SUBDIRS += online-accounts/icons\n" \
		panels/Makefile.am || return 1
	grep -Fqx "SUBDIRS += online-accounts/icons" panels/Makefile.am || return 1

	# Fix metadata path #
	sed -i \
		-e "/appdatadir/{s/\/appdata/\/metainfo/}" \
		shell/appdata/Makefile.am || return 1
	grep -Fqx 'appdatadir = $(datadir)/metainfo' shell/appdata/Makefile.am || return 1

	# Add more themes and accent colors #
	sed -i \
		-e 's/\(themes_id\[] = {\)/\1 "Adwaita", "Ambiance", "Radiance", "HighContrast",/' \
		-e 's/\(themes_name\[] = {\)/\1 "Adwaita", "Ambiance", "Radiance", "High Contrast",/' \
		-e 's/\(colors_id\[] = {\)/\1 "Adwaita", "ubuntu-mono-dark", "ubuntu-mono-light", "HighContrast",/' \
		-e 's/\(colors_name\[] = {\)/\1 "Adwaita", "Ambiance", "Radiance", "High Contrast",/' \
		-e '/colors_id/{s/"Yaru-viridian-dark"/"Yaru-viridian-dark", "Yaru-wartybrown", "Yaru-wartybrown-dark", "Yaru-yellow", "Yaru-yellow-dark"/}' \
		-e '/colors_name/{s/"Viridian (Yaru-dark)"/"Viridian (Yaru-dark)", "Warty Brown (Yaru)", "Warty Brown (Yaru-dark)", "Yellow (Yaru)", "Yellow (Yaru-dark)"/}' \
		panels/appearance/cc-appearance-panel.c || return 1
	grep -Eq 'themes_id\[\] = \{ "Adwaita", "Ambiance", "Radiance", "HighContrast", "Yaru"' \
		panels/appearance/cc-appearance-panel.c || return 1
	grep -Eq 'themes_name\[\] = \{ "Adwaita", "Ambiance", "Radiance", "High Contrast", "Yaru"' \
		panels/appearance/cc-appearance-panel.c || return 1
	grep -Eq 'colors_id\[\] = \{ "Adwaita", "ubuntu-mono-dark", .*"Yaru-yellow-dark" \}' \
		panels/appearance/cc-appearance-panel.c || return 1
	grep -Eq 'colors_name\[\] = \{ "Adwaita", "Ambiance", .*"Yellow \(Yaru-dark\)" \}' \
		panels/appearance/cc-appearance-panel.c || return 1
}
