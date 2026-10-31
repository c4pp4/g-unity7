OVERLAY_PKG="unity-base/unity-control-center"
UBUNTU_SRC="unity-control-center"
GROUP="desktop"

## The default USE flags of the ebuild (+cups: printers-fix_launcher.patch).
##  01-langselector.patch and 02-optional-bt-colord-kerberos-wacom.patch only
##  replace Ubuntu tools Gentoo lacks and make dependencies optional.
PATCHES=(
	appearance-ignore_screenshots_from_mate_screenshot.patch
	appearance-process_filename_dark_files.patch
	network-fix-hotspot-button-state.patch
	sharing-fix_translation.patch
	shell-fix_theme_selection_and_hover.patch
	use-cinnamon-schema-for-idle-delay.patch
	printers-fix_launcher.patch
)

debian_edit() {
	# The metadata are installed to usr/share/metainfo (Fix metadata path) #
	sed -i -e "s:usr/share/appdata:usr/share/metainfo:" debian/unity-control-center.install || return 1
	grep -Fq "usr/share/metainfo" debian/unity-control-center.install || return 1
}

src_edit() {
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
