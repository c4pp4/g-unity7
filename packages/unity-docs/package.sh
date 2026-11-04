## Derived source: ubuntu-docs of xenial, the last one with the help of Unity
##  (help:ubuntu-help, linked from unity-control-center, mate-utils and
##  indicator-session). ubuntu-docs of the current series has only pages of
##  gnome-help, the help id ubuntu-help is free.
OVERLAY_PKG="unity-base/ubuntu-docs"
UBUNTU_SRC="ubuntu-docs"
UBUNTU_SERIES="xenial"
SOURCE_NAME="unity-docs"
GROUP="desktop"

debian_edit() {
	sed -i \
		-e "s/^Package: ubuntu-docs$/Package: unity-docs/" \
		-e "s/^Maintainer: .*/Maintainer: ${DEBFULLNAME} <${DEBEMAIL}>/" \
		-e "/^Vcs-/d" \
		-e "s/^Description: Ubuntu Desktop Guide$/Description: G Unity⁷ Desktop Guide, the help of Unity7/" \
		-e "s/^ This package holds the official Ubuntu-specific documentation, maintained $/ The help of the Unity7 desktop from ubuntu-docs of Ubuntu 16.04 (the last/" \
		-e "s/^ by the Ubuntu Documentation Team. The documentation can be viewed using$/ one with it), maintained by the Ubuntu Documentation Team. It can be viewed/" \
		-e "s/^ Yelp, the GNOME help browser.$/ using Yelp, the GNOME help browser (help:ubuntu-help)./" \
		debian/control || return 1
	grep -qx "Package: unity-docs" debian/control || return 1
	grep -qx " using Yelp, the GNOME help browser (help:ubuntu-help)." debian/control || return 1
	! grep -q "^Vcs-\|Ubuntu-specific" debian/control || return 1

	# cdbs has no gnome.mk any more: dh with autoreconf (YELP_HELP_INIT of yelp-tools) #
	sed -i \
		-e "s/^Build-Depends: debhelper (>= 8), cdbs$/Build-Depends: debhelper-compat (= 13)/" \
		-e "/^Build-Depends-Indep: gnome-common,$/{N;s/gnome-common,\n *//}" \
		debian/control || return 1
	grep -qx "Build-Depends: debhelper-compat (= 13)" debian/control || return 1
	! grep -q "cdbs\|gnome-common" debian/control || return 1
	rm debian/compat || return 1
	printf '#!/usr/bin/make -f\n\n%%:\n\tdh $@\n' > debian/rules || return 1
	grep -qxF "$(printf '\tdh $@')" debian/rules || return 1

	# Removes an alternative of firefox-homepage of 11.04 #
	rm debian/ubuntu-docs.preinst || return 1
}

src_edit() {
	local f
	local -a pages po_files

	pushd ubuntu-help >/dev/null || return 1
		# Ubuntu Software Center is not in Ubuntu any more #
		sed -i -e "/addremove/d" Makefile.am || return 1
		! grep -q "addremove" Makefile.am || return 1
		sed -i -e "s/ addremove//" C/index.page || return 1
		! grep -q "addremove" C/index.page || return 1

		# Corrections (itstool: Segmentation fault (core dumped) #
		sed -i \
			-e "s/e gui>/e <gui>/" \
			-e "s/<em\.s/<em>s/" \
			-e "s|modul<em>|modul</em>|" \
			-e 's/"em>F/"<em>F/' \
			-e "s|edky<gui>|edky</gui>|" \
			-e "s/<Ch/<gui>Ch/" \
			cs/cs.po || return 1
		! grep -q -e "e gui>" -e "<em\.s" -e "modul<em>" -e '"em>F' -e "edky<gui>" -e "<Ch" cs/cs.po || return 1

		sed -i "s/k<gui>/k<\/gui>/" da/da.po || return 1
		! grep -q "k<gui>" da/da.po || return 1

		sed -i \
			-e 's|"<key>Ctrl</key><|"<keyseq><key>Ctrl</key><|' \
			-e "s/guι/gui/" \
			el/el.po || return 1
		! grep -q -e '"<key>Ctrl</key><' -e "guι" el/el.po || return 1

		sed -i "s|ー&|ー/|" ja/ja.po || return 1
		! grep -q "ー&" ja/ja.po || return 1

		sed -i \
			-e "s/<gui>Configurações do Sistema<guiseq>/<guiseq><gui>Configurações do Sistema/" \
			-e "s/ <link\././" \
			-e "s/ & / \&amp; /" \
			pt/pt.po || return 1
		! grep -q -e "<gui>Configurações do Sistema<guiseq>" -e " <link\." -e " & " pt/pt.po || return 1

		sed -i 's/"link href=\\//' ru/ru.po || return 1
		! grep -q '"link href=\\' ru/ru.po || return 1

		sed -i "s/ gui>/<gui>/" tr/tr.po || return 1
		! grep -q " gui>" tr/tr.po || return 1

		sed -i \
			-e "s|<link xref=\\\\\\\||" \
			-e "s/قېتىم <link/قېتىم/" \
			-e "s|دا كۆرسەت<gui>|دا كۆرسەت</gui>|" \
			-e 's|xref=\\"shell-exit\\">چېكىنى|<link xref=\\"shell-exit\\">|' \
			-e 's|\\"#files\\\\\\"/>|<link xref=\\"#files\\"/>|' \
			-e 's|<link xref=\\\\\\"#folders\\\\\\"/>|<link xref=\\"#folders\\"/>|' \
			-e 's|\\"nautilus-behavior#executable\\\\\\\"/>|<link xref=\\"nautilus-behavior#executable\\"/>|' \
			-e "s/ app>/<app>/" \
			-e "s/ gui>/<gui>/" \
			ug/ug.po || return 1
		! grep -q -e "قېتىم <link" -e "دا كۆرسەت<gui>" -e " app>" -e " gui>" ug/ug.po || return 1
	popd >/dev/null || return 1

	# G Unity⁷ instead of the Ubuntu desktop (the Ubuntu logo and button of #
	#  the Dash stay, as the icon of the Dash of Ubuntu Unity) #
	mapfile -t pages < <(find ubuntu-help -maxdepth 2 -type f -name "*.page")
	for f in ubuntu-help/*/*.po; do
		po_files+=( "${f}" )
	done
	sed -i \
		-e "s/Ubuntu Desktop/G Unity⁷ Desktop/" \
		-e "s/Ubuntu desktop/G Unity⁷ Desktop/" \
		-e "s/Welcome to Ubuntu/Welcome to G Unity⁷/" \
		-e "s/Ubuntu features/G Unity⁷ features/" \
		"${pages[@]}" "${po_files[@]}" || return 1
	## The translations of the changed messages (the lines up to the next comment)
	sed -i ":bgn;/Unity⁷/{:loop;n;/^#/b bgn;s/Ubuntu/G Unity⁷/g;b loop;}" "${po_files[@]}" || return 1
	grep -q "<title type='text'>G Unity⁷ Desktop Guide</title>" ubuntu-help/C/index.page || return 1
	! grep -q "Ubuntu Desktop\|Ubuntu desktop\|Welcome to Ubuntu\|Ubuntu features" "${pages[@]}" || return 1
	grep -q "G Unity⁷" ubuntu-help/cs/cs.po || return 1
}
