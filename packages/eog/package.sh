OVERLAY_PKG="ehooks/media-gfx/eog:1"
UBUNTU_SRC="eog"
GROUP="desktop"

PATCHES=(
	0001-Add-a-traditional-menu-bar.patch
)

src_edit() {
	local lang

	# Menu bar translations (0001-Add-a-traditional-menu-bar.patch) #
	merge_translations "${FILESDIR}"/global-menu-translations-xenial.tar.xz || return 1

	# The menu bar in its own text domain, eog-menubar. Ubuntu's language packs #
	#  install an eog.mo without the menu bar strings in /usr/share/locale-langpack, #
	#  which gettext prefers to the eog.mo of this package in /usr/share/locale #
	sed -i -e 's/^<interface>$/<interface domain="eog-menubar">/' data/eog-menubar.ui || return 1
	grep -qx '<interface domain="eog-menubar">' data/eog-menubar.ui || return 1
	mkdir po-menubar || return 1
	echo "data/eog-menubar.ui" > po-menubar/POTFILES.in || return 1
	python3 -I - data/eog-menubar.ui > po-menubar/eog-menubar.pot <<-'EOF' || return 1
		import re, sys, xml.etree.ElementTree as ET
		labels = []
		for node in ET.parse(sys.argv[1]).iter():
		    if node.get("translatable") == "yes" and node.text and node.text not in labels:
		        labels.append(node.text)
		print('msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n')
		for label in labels:
		    print('msgid "%s"\nmsgstr ""\n' % re.sub(r'(["\\])', r'\\\1', label))
	EOF
	[[ $(grep -c '^msgid "..*"$' po-menubar/eog-menubar.pot) -gt 30 ]] || return 1
	for lang in $(grep -v '^#' po/LINGUAS); do
		msgmerge --quiet --no-fuzzy-matching -o - po/"${lang}".po po-menubar/eog-menubar.pot \
			| msgattrib --translated --no-obsolete -o po-menubar/"${lang}".po || return 1
		# Keep the languages with a translated label besides the header #
		if [[ $(grep -c '^msgid ' po-menubar/"${lang}".po 2>/dev/null) -gt 1 ]]; then
			echo "${lang}" >> po-menubar/LINGUAS || return 1
		else
			rm -f po-menubar/"${lang}".po || return 1
		fi
	done
	rm po-menubar/eog-menubar.pot || return 1
	grep -qx "cs" po-menubar/LINGUAS || return 1
	echo "i18n.gettext('eog-menubar', preset: 'glib')" > po-menubar/meson.build || return 1
	sed -i -e "s/^subdir('po')$/&\nsubdir('po-menubar')/" meson.build || return 1
	grep -qx "subdir('po-menubar')" meson.build || return 1
}
