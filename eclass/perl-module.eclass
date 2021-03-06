# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/eclass/perl-module.eclass,v 1.160 2014/12/13 21:06:07 dilfridge Exp $

# @ECLASS: perl-module.eclass
# @MAINTAINER:
# perl@gentoo.org
# @AUTHOR:
# Seemant Kulleen <seemant@gentoo.org>
# @BLURB: eclass for perl modules
# @DESCRIPTION:
# The perl-module eclass is designed to allow easier installation of perl
# modules, and their incorporation into the Gentoo Linux system.

inherit eutils multiprocessing unpacker
[[ ${CATEGORY} == "perl-core" ]] && inherit alternatives

PERL_EXPF="src_unpack src_compile src_test src_install"

case "${EAPI:-0}" in
	4|5)
		PERL_EXPF+=" src_prepare src_configure"
		[[ ${CATEGORY} == "perl-core" ]] && \
			PERL_EXPF+=" pkg_postinst pkg_postrm"

		case "${GENTOO_DEPEND_ON_PERL:-yes}" in
		yes)
			case "${EAPI:-0}" in
			5)
				case "${GENTOO_DEPEND_ON_PERL_SUBSLOT:-yes}" in
				yes)
					DEPEND="dev-lang/perl:=[-build(-)]"
					;;
				*)
					DEPEND="dev-lang/perl[-build(-)]"
					;;
				esac
				;;
			*)
				DEPEND="|| ( >=dev-lang/perl-5.16 <dev-lang/perl-5.16[-build] )"
				;;
			esac
			RDEPEND="${DEPEND}"
			;;
		esac
		;;
	*)
		die "EAPI=${EAPI} is not supported by perl-module.eclass"
		;;
esac

case "${EAPI:-0}" in
	5)
		;;
	*)
		ewarn
		ewarn "******************************************************************"
		ewarn "${EBUILD}:"
		ewarn "Support for EAPI=${EAPI:-0} in perl-module.eclass will be removed"
		ewarn "on 1/Feb/2015. Please fix your overlay ebuilds to use EAPI=5."
		ewarn "******************************************************************"
		ewarn
		;;
esac

case "${PERL_EXPORT_PHASE_FUNCTIONS:-yes}" in
	yes)
		EXPORT_FUNCTIONS ${PERL_EXPF}
		;;
	no)
		debug-print "PERL_EXPORT_PHASE_FUNCTIONS=no"
		;;
	*)
		die "PERL_EXPORT_PHASE_FUNCTIONS=${PERL_EXPORT_PHASE_FUNCTIONS} is not supported by perl-module.eclass"
		;;
esac

LICENSE="${LICENSE:-|| ( Artistic GPL-1+ )}"

if [[ -n ${MY_PN} || -n ${MY_PV} || -n ${MODULE_VERSION} ]] ; then
	: ${MY_P:=${MY_PN:-${PN}}-${MY_PV:-${MODULE_VERSION:-${PV}}}}
	S=${MY_S:-${WORKDIR}/${MY_P}}
fi

[[ -z "${SRC_URI}" && -z "${MODULE_A}" ]] && \
	MODULE_A="${MY_P:-${P}}.${MODULE_A_EXT:-tar.gz}"
[[ -z "${SRC_URI}" && -n "${MODULE_AUTHOR}" ]] && \
	SRC_URI="mirror://cpan/authors/id/${MODULE_AUTHOR:0:1}/${MODULE_AUTHOR:0:2}/${MODULE_AUTHOR}/${MODULE_SECTION:+${MODULE_SECTION}/}${MODULE_A}"
[[ -z "${HOMEPAGE}" ]] && \
	HOMEPAGE="http://search.cpan.org/dist/${MY_PN:-${PN}}/"

SRC_PREP="no"
SRC_TEST="skip"
PREFER_BUILDPL="yes"

pm_echovar=""
perlinfo_done=false

# @FUNCTION: perl-module_src_unpack
# @USAGE: perl-module_src_unpack
# @DESCRIPTION:
# Unpack the ebuild tarball(s).
# This function is to be called during the ebuild src_unpack() phase.
perl-module_src_unpack() {
	debug-print-function $FUNCNAME "$@"

	unpacker_src_unpack
	has src_prepare ${PERL_EXPF} || perl-module_src_prepare
}

# @FUNCTION: perl-module_src_prepare
# @USAGE: perl-module_src_prepare
# @DESCRIPTION:
# Get the ebuild sources ready.
# This function is to be called during the ebuild src_prepare() phase.
perl-module_src_prepare() {
	debug-print-function $FUNCNAME "$@"
	has src_prepare ${PERL_EXPF} && \
	[[ ${PATCHES[@]} ]] && epatch "${PATCHES[@]}"
	debug-print "$FUNCNAME: applying user patches"
	epatch_user
	if [[ ${PERL_RM_FILES[@]} ]]; then
		debug-print "$FUNCNAME: stripping unneeded files"
		perl_rm_files "${PERL_RM_FILES[@]}"
	fi
	perl_fix_osx_extra
	esvn_clean
}

# @FUNCTION: perl-module_src_configure
# @USAGE: perl-module_src_configure
# @DESCRIPTION:
# Configure the ebuild sources.
# This function is to be called during the ebuild src_configure() phase.
perl-module_src_configure() {
	debug-print-function $FUNCNAME "$@"

	[[ ${SRC_PREP} = yes ]] && return 0
	SRC_PREP="yes"

	perl_set_version

	[[ -z ${pm_echovar} ]] && export PERL_MM_USE_DEFAULT=1
	# Disable ExtUtils::AutoInstall from prompting
	export PERL_EXTUTILS_AUTOINSTALL="--skipdeps"

	if [[ $(declare -p myconf 2>&-) != "declare -a myconf="* ]]; then
		local myconf_local=(${myconf})
	else
		local myconf_local=("${myconf[@]}")
	fi

	if [[ ( ${PREFER_BUILDPL} == yes || ! -f Makefile.PL ) && -f Build.PL ]] ; then
		einfo "Using Module::Build"
		if [[ ${DEPEND} != *virtual/perl-Module-Build* && ${PN} != Module-Build ]] ; then
			eqawarn "QA Notice: The ebuild uses Module::Build but doesn't depend on it."
			eqawarn "           Add virtual/perl-Module-Build to DEPEND!"
			if [[ -n ${PERLQAFATAL} ]]; then
				eerror "Bailing out due to PERLQAFATAL=1";
				die;
			fi
		fi
		set -- \
			--installdirs=vendor \
			--libdoc= \
			--destdir="${D}" \
			--create_packlist=0 \
			"${myconf_local[@]}"
		einfo "perl Build.PL" "$@"
		perl Build.PL "$@" <<< "${pm_echovar}" \
				|| die "Unable to build!"
	elif [[ -f Makefile.PL ]] ; then
		einfo "Using ExtUtils::MakeMaker"
		set -- \
			PREFIX=${EPREFIX}/usr \
			INSTALLDIRS=vendor \
			INSTALLMAN3DIR='none' \
			DESTDIR="${D}" \
			"${myconf_local[@]}"
		einfo "perl Makefile.PL" "$@"
		perl Makefile.PL "$@" <<< "${pm_echovar}" \
				|| die "Unable to build!"
	fi
	if [[ ! -f Build.PL && ! -f Makefile.PL ]] ; then
		einfo "No Make or Build file detected..."
		return
	fi
}

# @FUNCTION: perl-module_src_prep
# @USAGE: perl-module_src_prep
# @DESCRIPTION:
# Configure the ebuild sources (bis).
#
# This function is still around for historical reasons 
# and will be soon deprecated.
#
# Please use the function above instead, perl-module_src_configure().
perl-module_src_prep() {
	debug-print-function $FUNCNAME "$@"
	ewarn "perl-modules.eclass: perl-module_src_prep is deprecated and will be removed. Please use perl-module_src_configure instead."
	perl-module_src_configure
}

# @FUNCTION: perl-module_src_compile
# @USAGE: perl-module_src_compile
# @DESCRIPTION:
# Compile the ebuild sources.
# This function is to be called during the ebuild src_compile() phase.
perl-module_src_compile() {
	debug-print-function $FUNCNAME "$@"
	perl_set_version

	has src_configure ${PERL_EXPF} || perl-module_src_prep

	if [[ $(declare -p mymake 2>&-) != "declare -a mymake="* ]]; then
		local mymake_local=(${mymake})
	else
		local mymake_local=("${mymake[@]}")
	fi

	if [[ -f Build ]] ; then
		./Build build \
			|| die "Compilation failed"
	elif [[ -f Makefile ]] ; then
		set -- \
			OTHERLDFLAGS="${LDFLAGS}" \
			"${mymake_local[@]}"
		einfo "emake" "$@"
		emake "$@" \
			|| die "Compilation failed"
#			OPTIMIZE="${CFLAGS}" \
	fi
}

# @FUNCTION: perl-module_src-test
# @USAGE: perl-module_src_test()
# @DESCRIPTION:
# This code attempts to work out your threadingness from MAKEOPTS
# and apply them to Test::Harness.
#
# If you want more verbose testing, set TEST_VERBOSE=1
# in your bashrc | /etc/portage/make.conf | ENV
#
# or ebuild writers:
# If you wish to enable default tests w/ 'make test' ,
#
#  SRC_TEST="do"
#
# If you wish to have threads run in parallel ( using the users makeopts )
# all of the following have been tested to work.
#
#  SRC_TEST="do parallel"
#  SRC_TEST="parallel"
#  SRC_TEST="parallel do"
#  SRC_TEST=parallel
#
perl-module_src_test() {
	debug-print-function $FUNCNAME "$@"
	if has 'do' ${SRC_TEST} || has 'parallel' ${SRC_TEST} ; then
		if has "${TEST_VERBOSE:-0}" 0 && has 'parallel' ${SRC_TEST} ; then
			export HARNESS_OPTIONS=j$(makeopts_jobs)
			einfo "Test::Harness Jobs=$(makeopts_jobs)"
		fi
		${perlinfo_done} || perl_set_version
		if [[ -f Build ]] ; then
			./Build test verbose=${TEST_VERBOSE:-0} || die "test failed"
		elif [[ -f Makefile ]] ; then
			emake test TEST_VERBOSE=${TEST_VERBOSE:-0} || die "test failed"
		fi
	fi
}

# @FUNCTION: perl-module_src_install
# @USAGE: perl-module_src_install
# @DESCRIPTION:
# Install a Perl ebuild.
# This function is to be called during the ebuild src_install() phase.
perl-module_src_install() {
	debug-print-function $FUNCNAME "$@"

	perl_set_version

	local f

	if [[ -z ${mytargets} ]] ; then
		case "${CATEGORY}" in
			dev-perl|perl-core) mytargets="pure_install" ;;
			*)                  mytargets="install" ;;
		esac
	fi

	if [[ $(declare -p myinst 2>&-) != "declare -a myinst="* ]]; then
		local myinst_local=(${myinst})
	else
		local myinst_local=("${myinst[@]}")
	fi

	if [[ -f Build ]] ; then
		./Build ${mytargets} \
			|| die "./Build ${mytargets} failed"
	elif [[ -f Makefile ]] ; then
		emake "${myinst_local[@]}" ${mytargets} \
			|| die "emake ${myinst_local[@]} ${mytargets} failed"
	fi

	perl_delete_module_manpages
	perl_delete_localpod
	perl_delete_packlist
	perl_remove_temppath

	for f in Change* CHANGES README* TODO FAQ ${mydoc}; do
		[[ -s ${f} ]] && dodoc ${f}
	done

	perl_link_duallife_scripts
}

# @FUNCTION: perl-module_pkg_setup
# @USAGE: perl-module_pkg_setup
# @DESCRIPTION:
# This function was to be called during the pkg_setup() phase.
# Deprecated, to be removed. Where it is called, place a call to perl_set_version instead.
perl-module_pkg_setup() {
	debug-print-function $FUNCNAME "$@"
	ewarn "perl-modules.eclass: perl-module_pkg_setup is deprecated and will be removed. Please use perl_set_version instead."
	perl_set_version
}

# @FUNCTION: perl-module_pkg_preinst
# @USAGE: perl-module_pkg_preinst
# @DESCRIPTION:
# This function was to be called during the pkg_preinst() phase.
# Deprecated, to be removed. Where it is called, place a call to perl_set_version instead.
perl-module_pkg_preinst() {
	debug-print-function $FUNCNAME "$@"
	ewarn "perl-modules.eclass: perl-module_pkg_preinst is deprecated and will be removed. Please use perl_set_version instead."
	perl_set_version
}

# @FUNCTION: perl-module_pkg_postinst
# @USAGE: perl-module_pkg_postinst
# @DESCRIPTION:
# This function is to be called during the pkg_postinst() phase. It only does 
# useful things for the perl-core category, where it handles the file renaming and symbolic
# links that prevent file collisions for dual-life packages installing scripts. 
# In any other category it immediately exits.
perl-module_pkg_postinst() {
	debug-print-function $FUNCNAME "$@"
	if [[ ${CATEGORY} != perl-core ]] ; then
		eqawarn "perl-module.eclass: You are calling perl-module_pkg_postinst outside the perl-core category."
		eqawarn "   This does not do anything; the call can be safely removed."
		return 0
	fi
	perl_link_duallife_scripts
}

# @FUNCTION: perl-module_pkg_prerm
# @USAGE: perl-module_pkg_prerm
# @DESCRIPTION:
# This function was to be called during the pkg_prerm() phase.
# It does not do anything. Deprecated, to be removed.
perl-module_pkg_prerm() {
	debug-print-function $FUNCNAME "$@"
	ewarn "perl-module.eclass: perl-module_pkg_prerm does not do anything and will be removed. Please remove the call."
}

# @FUNCTION: perl-module_pkg_postrm
# @USAGE: perl-module_pkg_postrm
# @DESCRIPTION:
# This function is to be called during the pkg_postrm() phase. It only does 
# useful things for the perl-core category, where it handles the file renaming and symbolic
# links that prevent file collisions for dual-life packages installing scripts. 
# In any other category it immediately exits.
perl-module_pkg_postrm() {
	debug-print-function $FUNCNAME "$@"
	if [[ ${CATEGORY} != perl-core ]] ; then
		eqawarn "perl-module.eclass: You are calling perl-module_pkg_postrm outside the perl-core category."
		eqawarn "   This does not do anything; the call can be safely removed."
		return 0
	fi
	perl_link_duallife_scripts
}

# @FUNCTION: perl_set_version
# @USAGE: perl_set_version
# @DESCRIPTION:
# Extract version information and installation paths from the current Perl 
# interpreter. 
#
# This sets the following variables: PERL_VERSION, SITE_ARCH, SITE_LIB, 
# ARCH_LIB, VENDOR_LIB, VENDOR_ARCH
#
# This function used to be called perlinfo as well.
perl_set_version() {
	debug-print-function $FUNCNAME "$@"
	debug-print "$FUNCNAME: perlinfo_done=${perlinfo_done}"
	${perlinfo_done} && return 0
	perlinfo_done=true

	local f version install{{site,vendor}{arch,lib},archlib}
	eval "$(perl -V:{version,install{{site,vendor}{arch,lib},archlib}} )"
	PERL_VERSION=${version}
	SITE_ARCH=${installsitearch}
	SITE_LIB=${installsitelib}
	ARCH_LIB=${installarchlib}
	VENDOR_LIB=${installvendorlib}
	VENDOR_ARCH=${installvendorarch}
}

# @FUNCTION: perlinfo
# @USAGE: perlinfo
# @DESCRIPTION:
# This function is deprecated.
# 
# Please use the function above instead, perl_set_version().
perlinfo() {
	debug-print-function $FUNCNAME "$@"
	ewarn "perl-modules.eclass: perlinfo is deprecated and will be removed. Please use perl_set_version instead."
	perl_set_version
}

# @FUNCTION: perl_delete_localpod
# @USAGE: perl_delete_localpod
# @DESCRIPTION:
# Remove stray perllocal.pod files in the temporary install directory D.
#
# This function used to be called fixlocalpod as well.
perl_delete_localpod() {
	debug-print-function $FUNCNAME "$@"

	find "${D}" -type f -name perllocal.pod -delete
	find "${D}" -depth -mindepth 1 -type d -empty -delete
}

# @FUNCTION: fixlocalpod
# @USAGE: fixlocalpod
# @DESCRIPTION:
# This function is deprecated. 
#
# Please use the function above instead, perl_delete_localpod().
fixlocalpod() {
	debug-print-function $FUNCNAME "$@"
	ewarn "perl-modules.eclass: fixlocalpod is deprecated and will be removed. Please use perl_delete_localpod instead."
	perl_delete_localpod
}

# @FUNCTION: perl_fix_osx_extra
# @USAGE: perl_fix_osx_extra
# @DESCRIPTION:
# Look through ${S} for AppleDouble encoded files and get rid of them.
perl_fix_osx_extra() {
	debug-print-function $FUNCNAME "$@"

	local f
	find "${S}" -type f -name "._*" -print0 | while read -rd '' f ; do
		einfo "Removing AppleDouble encoded Macintosh file: ${f#${S}/}"
		rm -f "${f}"
		f=${f#${S}/}
		grep -q "${f}" "${S}"/MANIFEST && \
			elog "AppleDouble encoded Macintosh file in MANIFEST: ${f#${S}/}"
	done
}

# @FUNCTION: perl_delete_module_manpages
# @USAGE: perl_delete_module_manpages
# @DESCRIPTION:
# Bump off manpages installed by the current module such as *.3pm files as well
# as empty directories.
perl_delete_module_manpages() {
	debug-print-function $FUNCNAME "$@"

	if [[ -d "${ED}"/usr/share/man ]] ; then
		find "${ED}"/usr/share/man -type f -name "*.3pm" -delete
		find "${ED}"/usr/share/man -depth -type d -empty -delete
	fi
}

# @FUNCTION: perl_delete_packlist
# @USAGE: perl_delete_packlist
# @DESCRIPTION:
# Look through ${D} for .packlist files, empty .bs files and empty directories,
# and get rid of items found.
perl_delete_packlist() {
	debug-print-function $FUNCNAME "$@"
	perl_set_version
	if [[ -d ${D}/${VENDOR_ARCH} ]] ; then
		find "${D}/${VENDOR_ARCH}" -type f -a \( -name .packlist \
			-o \( -name '*.bs' -a -empty \) \) -delete
		find "${D}" -depth -mindepth 1 -type d -empty -delete
	fi
}

# @FUNCTION: perl_remove_temppath
# @USAGE: perl_remove_temppath
# @DESCRIPTION:
# Look through ${D} for text files containing the temporary installation
# folder (i.e. ${D}). If the pattern is found (i.e. " text"), replace it with `/'.
perl_remove_temppath() {
	debug-print-function $FUNCNAME "$@"

	find "${D}" -type f -not -name '*.so' -print0 | while read -rd '' f ; do
		if file "${f}" | grep -q -i " text" ; then
			grep -q "${D}" "${f}" && ewarn "QA: File contains a temporary path ${f}"
			sed -i -e "s:${D}:/:g" "${f}"
		fi
	done
}

# @FUNCTION: perl_rm_files
# @USAGE: perl_rm_files "file_1" "file_2"
# @DESCRIPTION:
# Remove certain files from a Perl release and remove them from the MANIFEST
# while we're there.
#
# Most useful in src_prepare for nuking bad tests, and is highly recommended
# for any tests like 'pod.t', 'pod-coverage.t' or 'kwalitee.t', as what they
# test is completely irrelevant to end users, and frequently fail simply
# because the authors of Test::Pod... changed their recommendations, and thus
# failures are only useful feedback to Authors, not users.
#
# Removing from MANIFEST also avoids needless log messages warning
# users about files "missing from their kit".
perl_rm_files() {
	debug-print-function $FUNCNAME "$@"
	local skipfile="${T}/.gentoo_makefile_skip"
	local manifile="${S}/MANIFEST"
	local manitemp="${T}/.gentoo_manifest_temp"
	oldifs="$IFS"
	IFS="\n"
	for filename in "$@"; do
		einfo "Removing un-needed ${filename}";
		# Remove the file
		rm -f "${S}/${filename}"
		[[ -e "${manifile}" ]] && echo "${filename}" >> "${skipfile}"
	done
	if [[ -e "${manifile}" && -e "${skipfile}" ]]; then
		einfo "Fixing Manifest"
		grep -v -F -f "${skipfile}" "${manifile}" > "${manitemp}"
		mv -f -- "${manitemp}" "${manifile}"
		rm -- "${skipfile}";
	fi
	IFS="$oldifs"
}

# @FUNCTION: perl_link_duallife_scripts
# @USAGE: perl_link_duallife_scripts
# @DESCRIPTION:
# Moves files and generates symlinks so dual-life packages installing scripts do not
# lead to file collisions. Mainly for use in pkg_postinst and pkg_postrm, and makes 
# only sense for perl-core packages.
perl_link_duallife_scripts() {
	debug-print-function $FUNCNAME "$@"
	if [[ ${CATEGORY} != perl-core ]] || ! has_version ">=dev-lang/perl-5.8.8-r8" ; then
		return 0
	fi

	local i ff
	if has "${EBUILD_PHASE:-none}" "postinst" "postrm" ; then
		for i in "${DUALLIFESCRIPTS[@]}" ; do
			alternatives_auto_makesym "/${i}" "/${i}-[0-9]*"
		done
		for i in "${DUALLIFEMAN[@]}" ; do
			ff=`echo "${EROOT}"/${i%.1}-${PV}-${P}.1*`
			ff=${ff##*.1}
			alternatives_auto_makesym "/${i}${ff}" "/${i%.1}-[0-9]*"
		done
	else
		pushd "${ED}" > /dev/null
		for i in $(find usr/bin -maxdepth 1 -type f 2>/dev/null) ; do
			mv ${i}{,-${PV}-${P}} || die
			#DUALLIFESCRIPTS[${#DUALLIFESCRIPTS[*]}]=${i##*/}
			DUALLIFESCRIPTS[${#DUALLIFESCRIPTS[*]}]=${i}
		done
		for i in $(find usr/share/man/man1 -maxdepth 1 -type f 2>/dev/null) ; do
			mv ${i} ${i%.1}-${PV}-${P}.1 || die
			DUALLIFEMAN[${#DUALLIFEMAN[*]}]=${i}
		done
		popd > /dev/null
	fi
}
