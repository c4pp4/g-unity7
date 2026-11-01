OVERLAY_PKG="ehooks/app-backup/deja-dup"
UBUNTU_SRC="deja-dup"
GROUP="desktop"

src_edit() {
	# Make Deja Dup appear in unity-control-center #
	local desktop=data/app.desktop.in
	sed -i \
		-e "/^Exec=/{s/ %u//}" \
		-e "/^Categories=/{s/;\?$/;Settings;X-GNOME-SystemSettings;X-Unity-Settings-Panel;\nX-Unity-Settings-Panel=deja-dup/}" \
		"${desktop}" || return 1
	grep -q "^X-Unity-Settings-Panel=deja-dup$" "${desktop}" || return 1
}
