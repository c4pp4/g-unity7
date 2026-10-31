## Derived source: nemo-fileroller renamed for Engrampa, as in the overlay.
OVERLAY_PKG="gnome-extra/nemo-engrampa"
UBUNTU_SRC="nemo-fileroller"
SOURCE_NAME="nemo-engrampa"

debian_edit() {
	sed -i \
		-e "s/^Package: nemo-fileroller$/Package: nemo-engrampa/" \
		-e "s/^Depends: file-roller, /Depends: engrampa, /" \
		-e "s/^Description: File Roller integration for Nemo$/Description: Engrampa integration for Nemo/" \
		-e "s/Nemo File Roller is an Nemo extension/Nemo Engrampa is a Nemo extension/" \
		-e "s/^Maintainer: .*/Maintainer: ${DEBFULLNAME} <${DEBEMAIL}>/" \
		-e "/^Uploaders:/,/^[^ ]/{/^Uploaders:/d;/^ /d}" \
		-e "/^Vcs-/d" \
		debian/control || return 1
	grep -qx "Package: nemo-engrampa" debian/control || return 1
	grep -q "^Depends: engrampa, " debian/control || return 1
	! grep -qi "file.\?roller\|^Uploaders\|^Vcs-" debian/control || return 1
}

src_edit() {
	local f

	for f in src/*fileroller*; do
		mv "${f}" "${f/fileroller/engrampa}" || return 1
	done

	find . \( -path ./debian -o -path ./.git -o -path ./.pc \) -prune -o -type f -exec sed -i -E \
		-e 's:FILEROLLER:ENGRAMPA:' \
		-e 's:file[\ \-]?roller:engrampa:g' \
		-e 's:File[\ \-]?[rR]oller:Engrampa:g' \
		{} + || return 1
	[[ -f src/nemo-engrampa.c ]] || return 1
	! grep -rqE "file[ -]?roller|File[ -]?[rR]oller" --exclude-dir=debian --exclude-dir=.git --exclude-dir=.pc . || return 1
}
