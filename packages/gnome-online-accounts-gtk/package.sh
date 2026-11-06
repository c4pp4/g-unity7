OVERLAY_PKG="gnome-extra/gnome-online-accounts-gtk"
UBUNTU_SRC="gnome-online-accounts-gtk"
GROUP="desktop"

## The G Unity⁷ unity-control-center installs the unity-online-accounts icon.

src_edit() {
	# Make gnome-online-accounts-gtk appear in unity-control-center #
	sed -i \
		-e "/Categories/{s/Settings;/GNOME;GTK;Settings;DesktopSettings;X-Unity-Settings-Panel;X-GNOME-PersonalSettings;\nX-Unity-Settings-Panel=online-accounts/}" \
		-e "/Icon/{s/gnome-online-accounts-gtk/unity-online-accounts/}" \
		data/gnome-online-accounts-gtk.desktop.in.in || return 1
	grep -q "^X-Unity-Settings-Panel=online-accounts$" data/gnome-online-accounts-gtk.desktop.in.in || return 1
	grep -q "^Icon=unity-online-accounts$" data/gnome-online-accounts-gtk.desktop.in.in || return 1

	# Translate window title #
	sed -i \
		-e 's/title">/title" translatable="yes">/' \
		src/online-accounts.ui || return 1
	grep -Fq 'title" translatable="yes">' src/online-accounts.ui || return 1
}
