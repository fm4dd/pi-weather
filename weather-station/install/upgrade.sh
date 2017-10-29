#!/bin/bash
##########################################################
# upgrade.sh 20170624 Frank4DD
#
# This script upgrades a existing pi-weather installation.
#
# It is the first script to be run after downloading or
# cloning the latest git package. It expects to find the
# previous pi-weather station base directory within the
# same folder, e.g. under /home/pi.
#
# It needs to grab the existing pi-weather.conf to apply
# settings, and copies var and wcam content while making
# a zip backup for rollback.
#
# The script must be run as user "pi", it will use sudo
# if needed.
##########################################################
echo "upgrade.sh: Upgrading pi-weather software at `date`"

echo "##########################################################"
echo "# 1. Check for existing "pi-wsXX" directory"
echo "##########################################################"
OLDDIR=`ls -d ../../pi-ws*`
if [[ ! -d $OLDDIR ]]; then
   echo "Error - cannot find old pi-weather folder [$OLDDIR]" >&2
   exit 1
fi
echo "Found old pi-weather folder [$OLDDIR]"
echo "Done."
echo

echo "##########################################################"
echo "# 2. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1;
fi
echo "OK, the user ID is [$EUID] = `whoami`"

echo "Done."
echo

echo "##########################################################"
echo "# 3. Copy the existing pi-wsXX/etc/pi-weather.conf to etc"
echo "##########################################################"
OLDCONF="$OLDDIR/etc/pi-weather.conf"
if [[ ! -f $OLDCONF ]]; then
   echo "Error - cannot find old pi-weather.conf file [$OLDCONF]" >&2
   exit 1
fi
echo "cp $OLDCONF ../etc/pi-weather.conf"
cp $OLDCONF ../etc/pi-weather.conf
ls -l ../etc/pi-weather.conf
echo "Done."
echo

echo "##########################################################"
echo "# 4. Backup the old data into a local dated zip file"
echo "#    (excluding the potentially large wcam archive)"
echo "##########################################################"
BACKUP="../backup/`basename $OLDDIR`-`date +%Y%m%d-%H%M`.zip"
echo "zip -r -J -x $OLDDIR/web/wcam/\* -v $BACKUP $OLDDIR"
zip -r -J -x $OLDDIR/web/wcam/\* -v $BACKUP $OLDDIR
ls -l $BACKUP
echo "Done"
echo

echo "##########################################################"
echo "# 5. Umount tmpfs from old pi-weather/var directory"
echo "##########################################################"
GREP=`mount | grep $OLDDIR/var`
if [[ $? == 0 ]]; then
   sudo umount -v $OLDDIR/var
else
   echo "$OLDDIR/var tmpfs is not mounted"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 6. Run setup.sh to build and install the new system"
echo "##########################################################"
./setup.sh
echo

# echo "##########################################################"
# echo "# End of Pi-Weather software upgrade."
# echo "##########################################################"
