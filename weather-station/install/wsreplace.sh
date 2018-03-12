#!/bin/bash
##########################################################
# wsreplace.sh <old-station-ip>       20171111 Frank4DD
#
# This script replaces a broken weather station by down-
# loading the necessary config and data from the old
# station. If the system was set up as a weather station,
# the old data and cron scripts get removed first.
#
# 1. get the following files: pi-wsXX/etc/pi-weather.conf
#                             pi-wsXX/rrd/*.rrd
#                             ~/.ssh.zip
#    save them locally into ~/pi-weather/backup/pi-wsXX.
# 2. Check for existing local weather station, zip it up
# 3. remove existing local weather station ramdisk mounts
# 4. Check for old weather station cron jobs, remove them
# 5. Copy the remote pi-weather.conf to ~/pi-weather/etc
# 6. Run ~/pi-weather/install/setup.sh
# 7. Copy the remote rrd files to local ~/pi-wsXX/rrd
# 8. Copy the remote .ssh/ key files to local ~/.ssh
# 9. Check if web server config file needs updating
# 10. Power off old station, halt, and power-on replacement
#
# This script requires the 'sshpass' package
##########################################################
if [ $# -eq 1 ]; then
   echo "wsreplace.sh: Run at `date` for $1"
else
   echo "Usage example: wsreplace.sh 192.168.179.244"
   echo "This script requires IP of the old weather station, exiting."
   exit -1;
fi

echo "##########################################################"
echo "# 0. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1;
fi
echo "OK, the user ID is [$EUID] = `whoami`"

if [ ! -f /usr/bin/sshpass ]; then
   echo "Error: Cannot find reuired /usr/bin/sshpass"
   exit -1
fi

echo "Done."
echo

echo "##########################################################"
echo "# 1. Get the remote $1 systems pi-wsXX data"
echo "##########################################################"
echo "Enter the SSH password for pi@$1:"
read -s sshpw
# get weather station ID
echo "ssh pi@$1 \"ls -d /home/pi/pi-ws*\""
NEWWS=`sshpass -p $sshpw ssh pi@$1 "ls -d /home/pi/pi-ws*"`
if [ $NEWWS != "" ]; then
   NEWWS=`basename $NEWWS`
   echo "Remote system $1 runs station ID: $NEWWS"
fi
# create backup dir
echo "mkdir ../backup/mv-$NEWWS"
mkdir ../backup/mv-$NEWWS
# get the remote rrd files
echo "scp pi@$1:/home/pi/pi-ws*/rrd/*.rrd ../backup/mv-$NEWWS"
sshpass -p $sshpw scp pi@$1:/home/pi/pi-ws*/rrd/*.rrd ../backup/mv-$NEWWS
# get the remote config file
echo "scp pi@$1:/home/pi/pi-ws*/etc/pi-weather.conf ../backup/mv-$NEWWS"
sshpass -p $sshpw scp pi@$1:/home/pi/pi-ws*/etc/pi-weather.conf ../backup/mv-$NEWWS
# get the remote ssh key files
echo "scp -r pi@$1:/home/pi/.ssh ../backup/mv-$NEWWS/ssh"
sshpass -p $sshpw scp -r pi@$1:/home/pi/.ssh ../backup/mv-$NEWWS/ssh

echo "##########################################################"
echo "# 2. Check for a local existing pi-wsXX directory."
echo "# Backup the old data into a local dated zip file"
echo "# (excluding the potentially large wcam archive)."
echo "##########################################################"
OLDDIR=`ls -d ../../pi-ws*`
OLDWS=`basename $OLDDIR`
if [[ -d $OLDDIR ]]; then
   echo "Found old pi-weather folder [$OLDDIR]"
   BACKUP="../backup/$OLDWS-`date +%Y%m%d-%H%M`.zip"
   echo "zip -r -J -x $OLDDIR/web/wcam/\* -v $BACKUP $OLDDIR"
   zip -r -J -x $OLDDIR/web/wcam/\* -v $BACKUP $OLDDIR
   ls -l $BACKUP
   echo "Deleting old pi-weather folder [$OLDDIR]"
   rm -rf $OLDDIR
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
echo "# 5. Copy the remote pi-weather.conf to ~/pi-weather/etc "
echo "##########################################################"
# If we got a remote config, copy it into place for local use
if [ -f ../backup/mv-$NEWWS/pi-weather.conf ]; then
   echo "cp ../backup/mv-$NEWWS/pi-weather.conf ../etc/pi-weather.conf"
   cp ../backup/mv-$NEWWS/pi-weather.conf ../etc/pi-weather.conf
fi

echo "Done."
echo

echo "##########################################################"
echo "# 6. Run ~/pi-weather/install/setup.sh with the new config"
echo "##########################################################"
echo " ./setup.sh"
./setup.sh
echo "Done."
echo

echo "##########################################################"
echo "# 7. Copy remote DB files collected in 1. to ~/pi-wsXX/rrd"
echo "##########################################################"
# If we got remote RRD files, copy them into place for local use.
# If we got a problem in this step, we should not proceed further.
# Before we start, check if the previous step created the homedir.
if [ ! -d /home/pi/$NEWWS ]; then
   echo "Error: The new work directory /home/pi/$NEWWS doesn't exist"
   exit -1;
fi

if [ -f ../backup/mv-$NEWWS/weather.rrd ]; then
   echo "cp ../backup/mv-$NEWWS/weather.rrd /home/pi/$NEWWS/rrd."
   cp ../backup/mv-$NEWWS/weather.rrd /home/pi/$NEWWS/rrd
else
   echo "Error: Cannot find ../backup/mv-$NEWWS/weather.rrd";
   exit -1;
fi

if [ -f ../backup/mv-$NEWWS/rpitemp.rrd ]; then
   echo "cp ../backup/mv-$NEWWS/rpitemp.rrd /home/pi/$NEWWS/rrd."
   cp ../backup/mv-$NEWWS/rpitemp.rrd /home/pi/$NEWWS/rrd
else
   exit -1;
fi

echo "Done."
echo

echo "##########################################################"
echo "# 8. Copy the remote .ssh/ key files to local ~/.ssh dir"
echo "##########################################################"

if [ ! -d /home/pi/.ssh ]; then
   echo "We have no ~/.ssh folder, creating it now"
   echo "mkdir /home/pi/.ssh"
   mkdir /home/pi/.ssh
   echo "chmod 700 .ssh"
   chmod 700 .ssh
fi

if [ -f /home/pi/.ssh/id_rsa ]; then
   echo "We already have a local SSH key, creating a backup"
   echo "cp /home/pi/.ssh/id_rsa /home/pi/.ssh/id_rsa.orig"
   cp /home/pi/.ssh/id_rsa /home/pi/.ssh/id_rsa.orig
fi
if [ -f /home/pi/.ssh/id_rsa.pub ]; then
   echo "cp /home/pi/.ssh/id_rsa.pub /home/pi/.ssh/id_rsa.pub.orig"
   cp /home/pi/.ssh/id_rsa.pub /home/pi/.ssh/id_rsa.pub.orig
fi

if [ -f ../backup/mv-$NEWWS/ssh/id_rsa.pub ]; then
   echo "We got a remote SSH key, copy it into place for local use"
   echo "cp ../backup/mv-$NEWWS/ssh/id_rsa.pub /home/pi/.ssh/id_rsa.pub"
   cp ../backup/mv-$NEWWS/ssh/id_rsa.pub /home/pi/.ssh/id_rsa.pub
   echo "chmod 600 /home/pi/.ssh/id_rsa.pub"
   chmod 600 /home/pi/.ssh/id_rsa.pub
fi
if [ -f ../backup/mv-$NEWWS/ssh/id_rsa ]; then
   echo "cp ../backup/mv-$NEWWS/ssh/id_rsa /home/pi/.ssh/id_rsa"
   cp ../backup/mv-$NEWWS/ssh/id_rsa /home/pi/.ssh/id_rsa
   echo "chmod 600 /home/pi/.ssh/id_rsa"
   chmod 600 /home/pi/.ssh/id_rsa
fi

if [ -f ../backup/mv-$NEWWS/ssh/authorized_keys2 ]; then
   echo "The old station has a authorized_keys2 file, we adopt it"
   echo "cp ../backup/mv-$NEWWS/ssh/authorized_keys2 /home/pi/.ssh/authorized_keys2"
   cp ../backup/mv-$NEWWS/ssh/authorized_keys2 /home/pi/.ssh/authorized_keys2
   echo "chmod 600 /home/pi/.ssh/authorized_keys2"
   chmod 600 /home/pi/.ssh/authorized_keys2
fi

if [ ! -f /home/pi/.ssh/known_hosts ]; then
   echo "Could not find a hostkey file in .ssh, creating it"
   echo "touch /home/pi/.ssh/known_hosts"
   touch /home/pi/.ssh/known_hosts
   echo "chmod 600 /home/pi/.ssh/known_hosts"
   chmod 600 /home/pi/.ssh/known_hosts
fi

echo "Ensure we got the hostkey entry, otherwise sftp fails"
echo "sftp -o StrictHostKeychecking=no$NEWWS@weather.fm4dd.com <<EOT"
sftp -o StrictHostKeychecking=no $NEWWS@weather.fm4dd.com <<EOT
quit
EOT

echo "Done."
echo

echo "##########################################################"
echo "# 9. Check if local webserver config file needs updating #"
echo "##########################################################"
GREP=`grep "$HOMEDIR" /etc/lighttpd/lighttpd.conf | grep $NEWWS`
if [[ $? > 0 ]]; then
   echo "Updating HOMEDIR line in /etc/lighttpd/lighttpd.conf file:"
   sudo sh -c "sed -i -e 's/\/pi\/pi-ws..\/web/\/pi\/$NEWWS\/web/' /etc/lighttpd/lighttpd.conf"
   echo "sudo systemctl restart lighttp"
   sudo systemctl restart lighttpd
else
   echo "Found correct HOMEDIR line in /etc/lighttpd/lighttpd.conf file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 10. Stop remote system, reboot this system to take over."
echo "##########################################################"
echo "ssh pi@$1 \"sudo halt\""
#sshpass -p $sshpw ssh pi@$1 "sudo halt"

echo "sleep 10"
sleep 10

sync

echo "system power-off"
#power-off

echo "Done."
echo

############ end of wsreplace.sh #######################
