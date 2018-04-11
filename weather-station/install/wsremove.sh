#!/bin/bash
##########################################################
# wsremove.sh <station-id>           20171119 Frank4DD
#
# This script removes the weather station data and its 
# configuration data.

# 1. Check if we are root, this script is run as user pi
# 2. Check for existing local weather station, zip it up
# 3. remove existing local weather station ramdisk mounts
# 4. Check for old weather station cron jobs, remove them
# 5. Restore web server config file to original
# 6. Remove the old weather station data folder
#
##########################################################
if [ $# -eq 1 ]; then
   echo "wsremove.sh: Run at `date` for $1"
else
   echo "Usage example: wsremove.sh pi-ws01"
   echo "This script requires the ID of the weather station, exiting."
   exit -1;
fi

echo "##########################################################"
echo "# 1. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1;
fi
echo "OK, the user ID is [$EUID] = `whoami`"
echo "Done."
echo

echo "##########################################################"
echo "# 2. Backup the weather data into a local dated zip file"
echo "# (excluding the potentially large wcam archive)."
echo "##########################################################"
# get weather station ID
OLDWS=$1
TODAY=`date +'%Y%m%d'`
BACKUP="../backup/$TODAY-$OLDWS.zip"
OLDDIR=`ls -d /home/pi/$OLDWS`

if [[ -d $OLDDIR ]]; then
   echo "Found old pi-weather folder [$OLDDIR]"
   echo "zip -r -J -x $OLDDIR/web/wcam/\* -v $BACKUP $OLDDIR"
   zip -r -J -x $OLDDIR/web/wcam/\* -v $BACKUP $OLDDIR
   ls -l $BACKUP
fi
echo "Done"
echo

echo "#######################################################"
echo "# 3. Umount tmpfs from old pi-weather/var directory"
echo "#######################################################"
GREP=`mount | grep $OLDDIR/var`
if [[ $? == 0 ]]; then
   sudo umount -v $OLDDIR/var
else
   echo "$OLDDIR/var tmpfs is not mounted"
fi

GREP=`grep $OLDDIR/var /etc/fstab`
if [[ $? == 0 ]]; then
   echo "Found old weather station entries in fstab."
   cp /etc/fstab ../backup/$TODAY-fstab.backup
   echo "Created a backup of current /etc/fstab file:"
   ls -l ../backup/$TODAY-fstab.backup
   echo "Removing old weather station fstab entries."
   sudo sh -c "sed -i -e '/##########################################################/d' /etc/fstab"
   sudo sh -c "sed -i -e '/# pi-weather:/d' /etc/fstab"
   sudo sh -c "sed -i -e '/tmpfs/d' /etc/fstab"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 4. Check for old crontab entries and remove them"
echo "##########################################################"
GREP=`grep $OLDDIR/bin /etc/crontab`
if [[ $? == 0 ]]; then
   echo "Found old weather station crontab entries."
   cp /etc/crontab ../backup/$TODAY-crontab.backup
   echo "Created a backup of current /etc/crontab file:"
   ls -l ../backup/$TODAY-crontab.backup
   echo "Removing old weather station crontab entries."
   sudo sh -c "sed -i -e '/##########################################################/d' /etc/crontab"
   sudo sh -c "sed -i -e '/# pi-weather:/d' /etc/crontab"
   sudo sh -c "sed -i -e '/$OLDWS/d' /etc/crontab"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 5. Check if local webserver config file needs updating #"
echo "##########################################################"
GREP=`grep "server.document-root" /etc/lighttpd/lighttpd.conf | grep $OLDWS`
if [[ $? > 0 ]]; then
   echo "Updating HOMEDIR line in /etc/lighttpd/lighttpd.conf file:"
   sudo sh -c "sed -i -e 's/\/home\/pi\/$OLDWS\/web/\/var\/www\/html/' /etc/lighttpd/lighttpd.conf"
   echo "sudo systemctl restart lighttp"
   sudo systemctl restart lighttpd
else
   echo "Found correct HOMEDIR line in /etc/lighttpd/lighttpd.conf file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 6. Remove the old weather station folder"
echo "##########################################################"
echo "sudo rm -r /home/pi/$OLDWS"
#rm -r $OLDWS
sync
echo "Done."
echo

echo "##########################################################"
echo "# 7. Setting local hostname to back to \"raspi\""
echo "##########################################################"
GREP=`grep "$OLDWS" /etc/hostname`
if [[ $? == 0 ]]; then
   sudo sh -c "echo raspi > /etc/hostname"
   echo "Updated \"raspi\" in /etc/hostname"
else
   echo "Found other hostname in /etc/hostname file:"
   echo "$GREP"
fi

GREP=`egrep '127\.0\.1\.1.*$OLDWS' /etc/hosts`
if [[ $? > 0 ]]; then
   sudo sh -c "sed -i -e 's/127\.0\.1\.1.*/127\.0\.1\.1       raspi/' /etc/hosts"
   echo "Updated hostname to \"raspi\" in /etc/hosts"
else
   echo "Found other hostname in /etc/hosts file:"
   echo "$GREP"
fi
echo "Done."
echo

############ end of wsremove.sh #######################
