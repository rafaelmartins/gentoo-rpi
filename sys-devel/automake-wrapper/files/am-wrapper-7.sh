#!/bin/sh
# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/sys-devel/automake-wrapper/files/am-wrapper-7.sh,v 1.1 2012/04/26 05:42:10 vapier Exp $

# Based on the am-wrapper.pl script provided by MandrakeSoft
# Rewritten in bash by Gregorio Guidi
#
# Executes the correct automake version.
#
# - defaults to newest version available (hopefully automake-1.12)
# - runs automake-1.X (where X is a valid automake version) if:
#   - envvar WANT_AUTOMAKE is set to `1.X'
#     -or-
#   - `Makefile.in' was generated by automake-1.X
#     -or-
#   - 'aclocal.m4' contain AM_AUTOMAKE_VERSION, specifying the use of 1.X

warn() { printf 'am-wrapper: %s: %b\n' "${argv0}" "$*" 1>&2; }
err() { warn "$@"; exit 1; }
unset IFS
which() {
	local p
	IFS=: # we don't use IFS anywhere, so don't bother saving/restoring
	for p in ${PATH} ; do
		p="${p}/$1"
		[ -e "${p}" ] && echo "${p}" && return 0
	done
	unset IFS
	return 1
}

#
# Sanitize argv[0] since it isn't always a full path #385201
#
argv0=${0##*/}
case ${0} in
	${argv0})
		# find it in PATH
		if ! full_argv0=$(which "${argv0}") ; then
			err "could not locate ${argv0}; file a bug"
		fi
		;;
	*)
		# re-use full/relative paths
		full_argv0=$0
		;;
esac

if [ "${argv0}" = "am-wrapper.sh" ] ; then
	err "Don't call this script directly"
fi

if ! seq 0 0 2>/dev/null 1>&2 ; then #338518
	seq() {
		local f l i
		case $# in
			1) f=1 i=1 l=$1;;
			2) f=$1 i=1 l=$2;;
			3) f=$1 i=$2 l=$3;;
		esac
		while :; do
			[ $l -lt $f -a $i -gt 0 ] && break
			[ $f -lt $l -a $i -lt 0 ] && break
			echo $f
			: $(( f += i ))
		done
		return 0
	}
fi

#
# Set up bindings between actual version and WANT_AUTOMAKE;
# Start with last known versions to speed up lookup process.
#
LAST_KNOWN_AUTOMAKE_VER="12"
vers=$(printf '1.%s ' `seq ${LAST_KNOWN_AUTOMAKE_VER} -1 4`)

find_binary() {
	local v
	all_vers="${all_vers} $*"
	for v in "$@" ; do
		if [ -x "${full_argv0}-${v}" ] ; then
			binary="${full_argv0}-${v}"
			return 0
		fi
	done
	return 1
}
binary=""
all_vers=""
if ! find_binary ${vers} ; then
	find_binary $(printf '1.%s ' `seq 99 -1 ${LAST_KNOWN_AUTOMAKE_VER}`)
fi

if [ -z "${binary}" ] ; then
	err "Unable to locate any usuable version of automake.\n" \
	    "\tI tried these versions:${all_vers}\n" \
	    "\tWith a base name of '${full_argv0}'."
fi

#
# Check the WANT_AUTOMAKE setting.  We accept a whitespace delimited
# list of automake versions.
#
if [ -n "${WANT_AUTOMAKE}" ] ; then
	for v in ${vers} x ; do
		if [ "${v}" = "x" ] ; then
			warn "warning: invalid WANT_AUTOMAKE '${WANT_AUTOMAKE}'; ignoring."
			unset WANT_AUTOMAKE
			break
		fi

		for wx in ${WANT_AUTOMAKE} ; do
			if [ "${wx}" = "${v}" ] ; then
				binary="${full_argv0}-${v}"
				v="x"
			fi
		done
		[ "${v}" = "x" ] && break
	done
fi

#
# autodetect helpers
#
do_awk() {
	local file=$1 ; shift
	local arg=$1 ; shift
	echo $(gawk "{ if (match(\$0, \"$*\", res)) { print res[${arg}]; exit } }" ${file})
}

#
# autodetect routine
#
if [ -z "${WANT_AUTOMAKE}" ] ; then
	if [ -r "Makefile.in" ] ; then
		confversion_mf=$(do_awk Makefile.in 2 "^# Makefile.in generated (automatically )?by automake ([0-9].[0-9]+)")
	fi
	if [ -r "aclocal.m4" ] ; then
		confversion_ac=$(do_awk aclocal.m4 1 'generated automatically by aclocal ([0-9].[0-9]+)')
		confversion_am=$(do_awk aclocal.m4 1 '[[:space:]]*\\[?AM_AUTOMAKE_VERSION\\(\\[?([0-9].[0-9]+)[^)]*\\]?\\)')
	fi

	for v in ${vers} ; do
		if [ "${confversion_mf}" = "${v}" ] || \
		   [ "${confversion_ac}" = "${v}" ] || \
		   [ "${confversion_am}" = "${v}" ]
		then
			binary="${full_argv0}-${v}"
			break
		fi
	done
fi

if [ -n "${WANT_AMWRAPPER_DEBUG}" ] ; then
	if [ -n "${WANT_AUTOMAKE}" ] ; then
		warn "DEBUG: WANT_AUTOMAKE is set to ${WANT_AUTOMAKE}"
	fi
	warn "DEBUG: will execute <${binary}>"
fi

#
# for further consistency
#
for v in ${vers} ; do
	if [ "${binary}" = "${full_argv0}-${v}" ] ; then
		export WANT_AUTOMAKE="${v}"
		break
	fi
done

#
# Now try to run the binary
#
if [ ! -x "${binary}" ] ; then
	# this shouldn't happen
	err "${binary} is missing or not executable.\n" \
	    "\tPlease try emerging the correct version of automake."
fi

exec "${binary}" "$@"

err "was unable to exec ${binary} !?"
