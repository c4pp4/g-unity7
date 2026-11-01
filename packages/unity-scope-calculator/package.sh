OVERLAY_PKG="unity-lens/unity-scope-extras"
UBUNTU_SRC="unity-scope-calculator"
GROUP="desktop"

PATCHES=(
	calculator.patch
)

debian_edit() {
	# Use mate-calc if gnome-calculator is not installed (calculator.patch) #
	sed -i -e "s/^\( *\)gnome-calculator,$/\1gnome-calculator | mate-calc,/" debian/control || return 1
	grep -q "^ *gnome-calculator | mate-calc,$" debian/control || return 1
}

src_edit() {
	# The icon of the installed calculator is shown (calculator.patch) #
	sed -i \
		-e "s/\['gnome-calculator', 'gnome-calculator-symbolic'\]/[self.scope_module.CALCULATOR_ICON, self.scope_module.CALCULATOR_ICON + '-symbolic']/" \
		tests/test_calculator.py || return 1
	grep -Fq "[self.scope_module.CALCULATOR_ICON, self.scope_module.CALCULATOR_ICON + '-symbolic']" tests/test_calculator.py || return 1

	# Don't install the scope daemon as a top-level Python module #
	sed -i "s/^setup(name=/setup(py_modules=[], packages=[], name=/" setup.py || return 1
	grep -Fq "setup(py_modules=[], packages=[], name=" setup.py || return 1
}
