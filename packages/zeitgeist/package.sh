OVERLAY_PKG="gnome-extra/zeitgeist"
UBUNTU_SRC="zeitgeist"

PATCHES=(
	do-not-start-datahub-in-unity.patch
	handle-termination-signals-in-main-loop.patch
	fix-build-with-xapian-2.patch
	skip-launch-events-without-launcher.patch
)

debian_edit() {
	local p=debian/patches/pre_populator.patch n

	# Fix pre_populator.patch with Ubuntu's mail clients from packages/zeitgeist/mail-clients #
	sed -i \
		-e "/rhythmbox/r ${FILESDIR}/music-clients" \
		-e '/Calculator/a +    arr.add (event_for_desktop_file ("mate-calc.desktop", ++ts));' \
		-e '/gedit/a +    arr.add (event_for_desktop_file ("pluma.desktop", ++ts));' \
		-e '/Totem/a +    arr.add (event_for_desktop_file ("org.gnome.Showtime.desktop", ++ts));' \
		-e '/Totem/a +    arr.add (event_for_desktop_file ("vlc.desktop", ++ts));' \
		-e "/thunderbird/r ${PKG_DIR}/mail-clients" \
		-e "s/rhythmbox/org.gnome.Rhythmbox3/" \
		"${p}" || return 1
	grep -Fq '"mate-calc.desktop"' "${p}" || return 1
	grep -Fq '"org.gnome.Showtime.desktop"' "${p}" || return 1
	grep -Fq '"org.gnome.Rhythmbox3.desktop"' "${p}" || return 1
	grep -Fq '"thunderbird_thunderbird.desktop"' "${p}" || return 1

	# The new file of the patch has as many lines as its hunk adds #
	n=$(awk '/^@@ -0,0 \+1,/ {h = 1; next} h && /^\+/ {n++; next} h {exit} END {print n}' "${p}")
	sed -i -e "s/^@@ -0,0 +1,[0-9]* @@/@@ -0,0 +1,${n} @@/" "${p}" || return 1
	grep -q "^@@ -0,0 +1,${n} @@" "${p}" || return 1
}
