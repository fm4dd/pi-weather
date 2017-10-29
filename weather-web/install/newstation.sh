#!/bin/bash
##########################################################
# newstation.sh 20170730 Frank4DD
#
# This script sets up a new weather station for receiving
# its data and processing int into the website.
#
# The script must be run as root, it will set ownership
# if needed.
##########################################################
readconfig() {
   local ARRAY="$1"
   local KEY VALUE
   local IFS='='
   declare -g -A "$ARRAY"
   while read; do
      # here assumed that comments may not be indented
      [[ $REPLY == [^#]*[^$IFS]${IFS}[^$IFS]* ]] && {
          read KEY VALUE <<< "$REPLY"
          [[ -n $KEY ]] || continue
          eval "$ARRAY[$KEY]=\"\$VALUE\""
      }
   done
}

echo "##########################################################"
echo "# 1. Check for "pi-web.conf" configfile, and source it"
echo "##########################################################"
CONFIG="../etc/pi-web.conf"
if [[ ! -f $CONFIG ]]; then
   echo "Error - cannot find config file [$CONFIG]" >&2
   exit 1
fi
readconfig MYCONFIG < "$CONFIG"
echo "Done."
echo

echo "##########################################################"
echo "# 2. Check if this script runs as root."
echo "##########################################################"
if (( $EUID != 0 )); then
   echo "This script must be run as user \"root\"."
   exit 1;
fi

echo "Done."
echo

echo "##########################################################"
echo "# 3. Query for the new weather station SID, e.g. \"pi-wsXX\""
echo "##########################################################"
read -p "Enter the new weather station SID number, 1-99: " SID
echo -e "\nOK Lets try using station SID [$SID]"

if [[ "$SID" =~ ^[0-9]$ ]] || [[ "$SID" =~ ^[0-9]{2}$ ]]; then
   echo "OK [$SID] is a two-dgit number."
else
   echo "Wrong format for [$SID], use a number between 1 and 99." 
   exit 1
fi

if [ $SID -gt 9 ]; then
   STATION=pi-ws$SID
else
   STATION=pi-ws0$SID
fi

echo "OK the station name is [$STATION]"
echo "Done"
echo

echo "##########################################################"
echo "# 4. Create the user ID for the new station $STATION:"
echo "##########################################################"
if [[ $SID -gt 9 ]]; then
   LINE1="$STATION:x:20$SID:200:weather station $SID:/srv/app/pi-web01/chroot/$STATION:/bin/false"
else
   LINE1="$STATION:x:200$SID:200:weather station 0$SID:/srv/app/pi-web01/chroot/$STATION:/bin/false"
fi
echo "Checking [$LINE1] in /etc/passwd"

GREP=`grep "$LINE1" /etc/passwd`

if [[ $? > 0 ]]; then
   echo "Adding 1 line to /etc/passwd file:"
   echo $LINE1 >> /etc/passwd
   tail -3 /etc/passwd
else
   echo "Found station name in /etc/passwd file:"
   echo "[$GREP]"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 5. Set strong password for the new station $STATION:"
echo "##########################################################"
echo "Checking [$STATION] in /etc/shadow"

GREP=`grep $STATION /etc/shadow`

if [[ $? > 0 ]]; then
   LINE1="pi-ws03::::::::"
   echo "Adding 1 line [$LINE1] to /etc/shadow file:"
   echo $LINE1 >> /etc/passwd
   tail -3 /etc/passwd
else
   echo "Found station name in /etc/shadow file:"
   echo "[$GREP]"
fi

echo "passwd $STATION"
passwd $STATION

echo "Done."
echo

echo "##########################################################"
echo "# 6. Create station data directory and subfolder structure"
echo "##########################################################"
DATADIR=${MYCONFIG[pi-web-data]}/chroot/$STATION

if [[ ! -d $DATADIR ]]; then
   echo "Create [$DATADIR] station data directory, owner root"
   mkdir $DATADIR
   chown root:root $DATADR
   echo "Create [$DATADIR/.ssh] sub-directory, owner $STATION"
   mkdir $DATADIR/.ssh
   chown $STATION:200 $DATADIR/.ssh
   echo "Create [$DATADIR/etc] sub-directory, owner $STATION"
   mkdir $DATADIR/etc
   chown $STATION:200 $DATADIR/etc
   echo "Create [$DATADIR/rrd] sub-directory, owner $STATION"
   mkdir $DATADIR/rrd
   chown $STATION:200 $DATADIR/rrd
   echo "Create [$DATADIR/var] sub-directory, owner $STATION"
   mkdir $DATADIR/var
   chown $STATION:200 $DATADIR/var
   echo "Create [$DATADIR/log] sub-directory, owner root"
   mkdir $DATADIR/log
else
   echo "Skipping creation, station folder [$DATADIR] exists."
fi
echo "Done."
echo

echo "##########################################################"
echo "# 7. Create station html directory and subfolder structure"
echo "##########################################################"
HTMLDIR=${MYCONFIG[pi-web-html]}/$STATION

if [[ ! -d $HTMLDIR ]]; then
   echo "Create [$HTMLDIR] station html directory"
   mkdir $HTMLDIR
else
   echo "Skipping creation, station folder [$HTMLDIR] exists."
fi

if [[ ! -d "$HTMLDIR/images" ]]; then
   echo "Create [$HTMLDIR/images] sub-directory"
   mkdir "$HTMLDIR/images"
else
   echo "Skipping creation, subfolder [$HTMLDIR/images] exists."
fi

echo "Done."
echo

echo "##########################################################"
echo "# 8. Check for and extract /tmp/$STATION-setup.zip"
echo "##########################################################"
IMPORTZIP=/tmp/$STATION-setup.zip

if [ -f $IMPORTZIP ]; then
   echo "mv $IMPORTZIP $DATADIR"
   mv $IMPORTZIP $DATADIR
   echo "mkdir $DATADIR/$STATION-setup"
   mkdir $DATADIR/$STATION-setup
   echo "unzip $DATADIR/$STATION-setup.zip -d $DATADIR/$STATION-setup"
   unzip $DATADIR/$STATION-setup.zip -d $DATADIR/$STATION-setup
else
   echo "No station setup file [$IMPORTZIP]"
fi

echo "##########################################################"
echo "# 9. Import $STATION RRD database to $DATADIR/rrd"
echo "##########################################################"
RRDFILE=$DATADIR/$STATION-setup/$STATION.xml

if [ -f $RRDFILE ]; then
   echo "Found $STATION RRD XML export file, restoring DB."
   echo "rrdtool restore $RRDFILE $DATADIR/rrd/$STATION.rrd"
   rrdtool restore $RRDFILE $DATADIR/rrd/$STATION.rrd
   echo "rm $RRDFILE"
   rm $RRDFILE
   echo "ls -l $DATADIR/rrd/$STATION.rrd"
   ls -l $DATADIR/rrd/$STATION.rrd
else
   echo "Could not find $RRDFILE"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 10. Copy $STATION config file to $DATADIR/etc"
echo "##########################################################"
ETCFILE=$DATADIR/$STATION-setup/$STATION.conf

if [ -f $ETCFILE ]; then
   echo "Found $STATION config file, importing."
   echo "mv $ETCFILE $DATADIR/etc"
   mv $ETCFILE $DATADIR/etc
   echo
   echo "ls -l $DATADIR/etc/$STATION.conf"
   ls -l $DATADIR/etc/$STATION.conf
else
   echo "Could not find $ETCFILE"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 11. Copy $STATION SSH key to $DATADIR/.ssh"
echo "##########################################################"
SSHFILE=$DATADIR/$STATION-setup/$STATION.pub

if [ -f $SSHFILE ]; then
   echo "Found $SSHFILE file, importing."
   echo "mv $SSHFILE $DATADIR/.ssh/authorized_keys2"
   mv $SSHFILE $DATADIR/.ssh/authorized_keys2
   echo "chown $STATION:200 $DATADIR/.ssh/authorized_keys2"
   chown $STATION:200 $DATADIR/.ssh/authorized_keys2
   echo "chmod 600 $DATADIR/.ssh/authorized_keys2"
   chmod 600 $DATADIR/.ssh/authorized_keys2
   echo
   echo "ls -l $DATADIR/.ssh/authorized_keys2"
   ls -l $DATADIR/.ssh/authorized_keys2
   echo "rmdir $DATADIR/$STATION-setup"
   rmdir $DATADIR/$STATION-setup
else
   echo "Could not find $SSHFILE"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 12. Copy $STATION index.php and showlog.php to $HTMLDIR"
echo "##########################################################"
WEBFILE1=../web/station-index.php

if [ -f $WEBFILE1 ]; then
   echo "Found $WEBFILE1 file, importing."
   echo "cp $WEBFILE1 $HTMLDIR/index.php"
   cp $WEBFILE1 $HTMLDIR/index.php
   echo "chown www-data:www-data $HTMLDIR/index.php"
   chown www-data:www-data $HTMLDIR/index.php
   echo "chmod 644 $HTMLDIR/index.php"
   chmod 644 $HTMLDIR/index.php
   echo
   echo "ls -l $HTMLDIR/index.php"
   ls -l $HTMLDIR/index.php
else
   echo "Could not find $WEBFILE1"
fi

WEBFILE2=../web/showlog.php

if [ -f $WEBFILE2 ]; then
   echo "Found $WEBFILE2 file, importing."
   echo "cp $WEBFILE2 $HTMLDIR/showlog.php"
   cp $WEBFILE2 $HTMLDIR/showlog.php
   echo "chown www-data:www-data $HTMLDIR/showlog.php"
   chown www-data:www-data $HTMLDIR/showlog.php
   echo "chmod 644 $HTMLDIR/showlog.php"
   chmod 644 $HTMLDIR/showlog.php
   echo
   echo "ls -l $HTMLDIR/showlog.php"
   ls -l $HTMLDIR/showlog.php
else
   echo "Could not find $WEBFILE2"
fi

echo "Done."
echo

echo "##########################################################"
echo " 14. Manual update /etc/crontab, adding the following line"
echo "##########################################################"
echo
echo "* * * * * root /srv/app/pi-web01/bin/rrdupdate.sh $STATION > /srv/app/pi-web01/chroot/$STATION/log/rrd.log 2>&1"

echo "Done."
echo

echo "##########################################################"
echo "# End of Pi-Weather station setup for $STATION."
echo "##########################################################"
