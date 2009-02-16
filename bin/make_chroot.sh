#!/bin/sh
# $Id$
#
# Script to generate a minimal chroot environment with Sun Java
# support to allow for Java programs to run in a chroot.
#
# This script downloads and installs a Debian base system.
# Minimum requirements: a Linux system with glibc >= 2.3, wget, ar and
# a POSIX shell in /bin/sh. About 250 MB disk space is needed. It must
# be run as root and will install the Debian debootstrap package.
#
# Part of the DOMjudge Programming Contest Jury System and licenced
# under the GNU GPL. See README and COPYING for details.

# Abort when a single command fails:
set -e

# Read command-line parameters:
CHROOTDIR=$1
ARCH=$2

# List of possible architectures to install chroot for:
ARCHLIST="alpha,amd64,arm,armel,hppa,i386,ia64,mips,mipsel,powerpc,s390,sparc"

# Debian packages to include during bootstrap process (comma separated):
INCLUDEDEBS=""

# Debian packages to install after upgrade (space separated):
INSTALLDEBS="sun-java6-jre"

# Debian packages to remove after upgrade (space separated):
REMOVEDEBS=""

# Debian mirror, modify to match closest mirror
#DEBMIRROR="http://ftp.us.debian.org/debian"
DEBMIRROR="http://ftp.nl.debian.org/debian"

# To prevent (libc6) upgrade questions:
export DEBIAN_FRONTEND=noninteractive

usage()
{
    echo "Usage: $0 <installdir> <architecture>"
    echo "Creates a chroot environment with Sun Java support using the"
    echo "Debian GNU/Linux distribution."
    echo
    echo "This script must be run as root, <installdir> the non-existing target"
    echo "location of the chroot and <architecture> one of the following:"
    echo "$ARCHLIST"
}

error()
{
    echo "Error: $@"
    echo
    usage
    exit 1
}

if [ `id -u` != 0 ]; then
    echo "Warning: you probably need to run this program as root."
fi

[ -z "$CHROOTDIR" ] && error "No installation directory given."
[ -z "$ARCH" ]      && error "No architecture given."
# TODO: test whether $ARCH is in $ARCHLIST? Maybe just warn?
[ -e "$CHROOTDIR" ] && error "'$CHROOTDIR' already exists, remove manually."

mkdir -p "$CHROOTDIR"
cd "$CHROOTDIR"
CHROOTDIR="$PWD"

if [ ! -x /usr/sbin/debootstrap ]; then
	if [ -f /etc/debian_version ]; then

		cd /
		apt-get install debootstrap

	else
		mkdir "$CHROOTDIR/debootstrap"
		cd "$CHROOTDIR/debootstrap"

		DEBOOTDEB="debootstrap_1.0.10lenny1_all.deb"
		wget "$DEBMIRROR/pool/main/d/debootstrap/${DEBOOTDEB}"

		ar -x "$DEBOOTDEB"
		cd /
		zcat "$CHROOTDIR/debootstrap/data.tar.gz" | tar xv

		rm -rf "$CHROOTDIR/debootstrap"
	fi
fi

INCLUDEOPT=""
if [ -n "$INCLUDEDEBS" ]; then
	INCLUDEOPT="--include=$INCLUDEDEBS"
fi
EXCLUDEOPT=""
if [ -n "$EXCLUDEDEBS" ]; then
	EXCLUDEOPT="--exclude=$EXCLUDEDEBS"
fi

echo "Running debootstrap to install base system, this may take a while..."
/usr/sbin/debootstrap $INCLUDEOPT $EXCLUDEOPT \
	--variant=minbase --arch "$ARCH" lenny "$CHROOTDIR" "$DEBMIRROR"

rm -f "$CHROOTDIR/etc/resolv.conf"
cp /etc/resolv.conf /etc/hostname "$CHROOTDIR/etc" || true

cat > "$CHROOTDIR/etc/apt/sources.list" <<EOF
# Different releases (incl. optional security repository):

# Stable (lenny)
deb $DEBMIRROR			lenny		main non-free contrib
deb http://security.debian.org	lenny/updates	main non-free contrib

# Testing
#deb $DEBMIRROR			testing		main non-free contrib
#deb http://security.debian.org	testing/updates	main non-free contrib

# Unstable
#deb $DEBMIRROR			unstable	main non-free contrib
EOF

cat > "$CHROOTDIR/etc/apt/apt.conf" <<EOF
APT::Get::Assume-Yes "true";
APT::Get::Force-Yes "false";
APT::Get::Purge "true";
APT::Install-Recommends "false";
Acquire::Retries "3";
Acquire::PDiffs "false";
EOF

# FIXME: do we also want to mount /sys?
mount -t proc proc "$CHROOTDIR/proc"

# Prevent perl locale warnings in the chroot:
export LC_ALL=C

chroot "$CHROOTDIR" /bin/sh -c debconf-set-selections <<EOF
passwd	passwd/root-password-crypted	password	
passwd	passwd/user-password-crypted	password	
passwd	passwd/root-password		password	
passwd	passwd/root-password-again	password	
passwd	passwd/user-password-again	password	
passwd	passwd/user-password		password	
passwd	passwd/shadow			boolean	true
passwd	passwd/username-bad		note	
passwd	passwd/password-mismatch	note	
passwd	passwd/username			string	
passwd	passwd/make-user		boolean	true
passwd	passwd/md5			boolean	false
passwd	passwd/user-fullname		string	
passwd	passwd/user-uid			string	
passwd	passwd/password-empty		note	
debconf	debconf/priority	select	high
debconf	debconf/frontend	select	Noninteractive
locales	locales/locales_to_be_generated	multiselect	
locales	locales/default_environment_locale	select	None
sun-java6-jre	sun-java6-jre/jcepolicy		note	
sun-java6-bin	shared/accepted-sun-dlj-v1-1	boolean	true
sun-java6-jre	shared/accepted-sun-dlj-v1-1	boolean	true
sun-java6-jre	sun-java6-jre/stopthread	boolean	true
sun-java6-bin	shared/present-sun-dlj-v1-1	note	
sun-java6-jre	shared/present-sun-dlj-v1-1	note	
sun-java6-bin	shared/error-sun-dlj-v1-1	error	
sun-java6-jre	shared/error-sun-dlj-v1-1	error	
EOF

chroot "$CHROOTDIR" /bin/sh -c "apt-get update && apt-get dist-upgrade"
chroot "$CHROOTDIR" /bin/sh -c "apt-get clean"
chroot "$CHROOTDIR" /bin/sh -c "apt-get install $INSTALLDEBS"
chroot "$CHROOTDIR" /bin/sh -c "apt-get remove $REMOVEDEBS"
chroot "$CHROOTDIR" /bin/sh -c "apt-get clean"

# Remove unnecessary setuid bits
chroot "$CHROOTDIR" /bin/sh -c "chmod a-s /usr/bin/wall /usr/bin/newgrp \
	/usr/bin/chage /usr/bin/chfn /usr/bin/chsh /usr/bin/expiry \
	/usr/bin/gpasswd /usr/bin/passwd /usr/lib/pt_chown \
	/bin/su /bin/mount /bin/umount /sbin/unix_chkpwd"

# Disable root account
sed -i "s/^root::/root:*:/" "$CHROOTDIR/etc/shadow"

umount "$CHROOTDIR/proc"

exit 0
