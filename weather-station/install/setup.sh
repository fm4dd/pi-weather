#!/bin/bash
##########################################################
# setup.sh 20170624 Frank4DD
#
# This script installs the pre-requsite software packages
# that are needed to compile the "pi-weather" programs,
# creates the folder structure, installs the database, etc.
#
# It is the first script to be run after downloading or
# cloning the git package. Before running it, copy the
# file etc/pi-weather.templ to etc/pi-weather.conf and
# edit its content to adjust configuration parameters.
#
# The script must be run as user "pi", it will use sudo
# if needed.
#
# Note: It adds approx 300MB of SW packages from needed
# RRD dev dependencies, video + image manipulation tools
# and lighthttpd webserver packages.
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
echo "# 1. Check for "pi-weather.conf" configfile, and source it"
echo "##########################################################"
CONFIG="../etc/pi-weather.conf"
if [[ ! -f $CONFIG ]]; then
   echo "Error - cannot find config file [$CONFIG]" >&2
   exit 1
fi
readconfig MYCONFIG < "$CONFIG"
echo "Done."
echo

echo "##########################################################"
echo "# 2. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1;
fi

echo "Done."
echo

echo "##########################################################"
echo "# 3. Check if the Raspberry Pi OS version is sufficient"
echo "##########################################################"
MAJOR=`lsb_release -r -s | cut -d "." -f1` # lsb_release -r -s 
MINOR=`lsb_release -r -s | cut -d "." -f2` # returns e.g. "9.4"

   echo "Rasbian release check: identified version $MAJOR.$MINOR"
if (( $MAJOR < 9 )); then
   echo "Error - pi-weather supports Rasbian Stretch Release 9 and up."
   exit 1;
fi

echo "Done."
echo

echo "##########################################################"
echo "# 4. Before we get SW packages, refresh the SW catalogue"
echo "# and remove any unneeded SW packages."
echo "##########################################################"
EXECUTE="sudo apt-get update"
echo "Updating SW catalogue through [$EXECUTE]. Please wait approx 60s"
#$EXECUTE | grep Reading
`$EXECUTE > /dev/null 2&>1`
echo

DELPKGS="libraspberrypi-doc samba-common cifs-utils libtalloc2 libwbclient0"
EXECUTE="sudo apt-get remove $DELPKGS -y -q"
echo "Removing SW packages [$DELPKGS]. Please wait ..."
$EXECUTE
if [[ $? > 0 ]]; then
   echo "Error removing packages [$DELPKGS], exiting setup script."
   echo "Check the apt function, network, and DNS."
   exit 1
fi

echo "Done."
echo

echo "##########################################################"
echo "# 5. Install tools and development headers for the I2C bus" 
echo "# supporting BME280, BMP180 sensors and I2C RTC modules"
echo "##########################################################"
APPLIST="i2c-tools libi2c-dev sshpass"
EXECUTE="sudo apt-get install $APPLIST -y -q"
echo "Getting SW packages [$APPLIST]. Please wait ..."
$EXECUTE
if [[ $? > 0 ]]; then
   echo "Error getting packages [$APPLIST], exiting setup script."
   echo "Check the apt function, network, and DNS."
   exit 1
fi
echo "Done."
echo

echo "##########################################################"
echo "# 6. Install the RRD database tools and development files"
echo "##########################################################"
APPLIST="rrdtool librrd8 librrd-dev"
EXECUTE="sudo apt-get install $APPLIST -y -q"
echo "Getting SW packages [$APPLIST]. Please wait ..."
$EXECUTE
if [[ $? > 0 ]]; then
   echo "Error getting packages [$APPLIST], exiting setup script."
   echo "Check the apt function, network, and DNS."
   exit 1
fi
echo "Done."
echo

echo "##########################################################"
echo "# 7. Install video creation tools: ffmpeg, imagemagick, zip"
echo "##########################################################"
APPLIST="ffmpeg imagemagick zip"
EXECUTE="sudo apt-get install $APPLIST -y -q"
echo "Getting SW packages [$APPLIST]. Please wait ..."
$EXECUTE
if [[ $? > 0 ]]; then
   echo "Error getting packages [$APPLIST], exiting setup script."
   echo "Check the apt function, network, and DNS."
   exit 1
fi
echo "Done."
echo

echo "##########################################################"
echo "# 8. Install webserver: lighttpd, lighttpd-doc, php-cgi"
echo "##########################################################"
APPLIST="lighttpd lighttpd-doc php-cgi php-mbstring rdate"
EXECUTE="sudo apt-get install $APPLIST -y -q"
echo "Getting SW packages [$APPLIST]. Please wait ..."
$EXECUTE
if [[ $? > 0 ]]; then
   echo "Error getting packages [$APPLIST], exiting setup script."
   echo "Check the apt function, network, and DNS."
   exit 1
fi
echo "Done."
echo

echo "##########################################################"
echo "# 9. Create the home directory and subfolder structure"
echo "##########################################################"
HOMEDIR=${MYCONFIG[pi-weather-dir]}
if [[ ! -d $HOMEDIR ]]; then
   echo "Create application directory [$HOMEDIR]"
   mkdir $HOMEDIR
   echo "Create sub-directory [$HOMEDIR/bin]"
   mkdir $HOMEDIR/bin
   echo "Create sub-directory [$HOMEDIR/var]"
   mkdir $HOMEDIR/var
   echo "Create sub-directory [$HOMEDIR/rrd]"
   mkdir $HOMEDIR/rrd
   echo "Create sub-directory [$HOMEDIR/etc]"
   mkdir $HOMEDIR/etc
   echo "Create sub-directory [$HOMEDIR/log]"
   mkdir $HOMEDIR/log
   echo "Create sub-directory [$HOMEDIR/web]"
   mkdir $HOMEDIR/web
   echo "Create sub-directory [$HOMEDIR/web/images]"
   mkdir $HOMEDIR/web/images
   echo "Create sub-directory [$HOMEDIR/web/wcam]"
   mkdir $HOMEDIR/web/wcam
else
   echo "Skipping creation, application directory [$HOMEDIR] exists."
fi
echo "Done."
echo

echo "##########################################################"
echo "# 10. Define HOMEDIR/var as tmpfs to reduce SD card wear"
echo "##########################################################"
TODAY=`date +'%Y%m%d'`
if [ -f ../backup/$TODAY-fstab.backup ]; then
   echo "Found existing backup of /etc/fstab file:"
   ls -l ../backup/$TODAY-fstab.backup
else
   echo "Create new backup of current /etc/fstab file:"
   cp /etc/crontab ../backup/$TODAY-fstab.backup
   ls -l ../backup/$TODAY-fstab.backup
fi
echo

GREP=`grep $HOMEDIR/var /etc/fstab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/fstab"
   LINE2="# pi-weather: Define $HOMEDIR/var as tmpfs, reducing sdcard wear"
   sudo sh -c "echo \"$LINE2\" >> /etc/fstab"
   LINE3="tmpfs           $HOMEDIR/var    tmpfs   nodev,nosuid,noexec,nodiratime,size=256M        0       0"
   sudo sh -c "echo \"$LINE3\" >> /etc/fstab"
   echo "Adding 3 lines to /etc/fstab file:"
   tail -4 /etc/fstab
else
   echo "Found $HOMEDIR/var tmpfs line in /etc/fstab file:"
   echo "$GREP"
fi

GREP=`mount | grep $HOMEDIR/var`
if [[ $? > 0 ]]; then
   sudo mount -v $HOMEDIR/var
else
   echo "Found $HOMEDIR/var tmpfs is already mounted"
fi
mount | grep $HOMEDIR/var
echo "Done."
echo

echo "##########################################################"
echo "# 11. Compile 'C' source code in ../src"
echo "##########################################################"
cd ../src
echo "Cleanup any old binaries in src:"
#make clean
echo
echo "Compile new binaries in src:"
make
echo

echo "##########################################################"
echo "# 12. Install programs and scripts to $HOMEDIR/bin"
echo "##########################################################"
export BINDIR=$HOMEDIR/bin
echo "Installing application binaries into $BINDIR."
#env | grep BINDIR
make install
echo
echo "List installed files in $BINDIR:"
ls -l $BINDIR
echo
unset BINDIR
echo -n "Returning to installer directory: "
cd -
echo "Done."
echo

echo "##########################################################"
echo "# 13. rrdcreate and rrdcreate2 creates empty RRD databases"
echo "##########################################################"
./rrdcreate.sh
RRD_DIR=${MYCONFIG[pi-weather-dir]}/rrd
RRD=$RRD_DIR/${MYCONFIG[pi-weather-rrd]}

if [[ ! -e $RRD ]]; then
   echo "Error creating the RRD database."
   exit 1
fi

ls -l $RRD

RRD2=$RRD_DIR/rpitemp.rrd
./rrdcreate2.sh
ls -l $RRD2

echo "Done."
echo

echo "##########################################################"
echo "# 14. Copy the "pi-weather.conf" file to $HOMEDIR/etc"
echo "##########################################################"
CONFIG="../etc/pi-weather.conf"
if [[ ! -f $CONFIG ]]; then
   echo "Error - cannot find config file [$CONFIG]" >&2
   exit 1
fi

if [[ -f $HOMEDIR/etc/pi-weather.conf ]]; then
   echo "Skipping configuration file copy, $HOMEDIR/etc/pi-weather.conf exists."
else
   echo "cp $CONFIG $HOMEDIR/etc"
   cp $CONFIG $HOMEDIR/etc
   chmod 644 $HOMEDIR/etc/pi-weather.conf
fi
ls -l $HOMEDIR/etc/pi-weather.conf
echo "Done."
echo

echo "##########################################################"
echo "# 15. Test the basic weatherstation functions"
echo "##########################################################"
./sensortest.sh
echo "./sensortest.sh returned [$?]"

if [[ $? > 0 ]]; then
   echo "Error - Test with ./sensortest.sh failed, exiting install." >&2
   exit 1
fi
echo

echo "##########################################################"
echo "# 16. Check SSH key for the data upload to Internet server"
echo "##########################################################"
PRIVKEY=`ls ~/.ssh/id_rsa`
PUBKEY=`ls ~/.ssh/id_rsa.pub`

if [ "$PRIVKEY" == "" ] || [ "$PUBKEY" == "" ]; then
   echo "Could not find existing SSH keys, generating 2048 bit RSA:"
   ssh-keygen -t rsa -b 2048 -C "pi-ws03" -f ~/.ssh/id_rsa -P "" -q
   PRIVKEY=`ls ~/.ssh/id_rsa`
   PUBKEY=`ls ~/.ssh/id_rsa.pub`
else
   echo "Found existing SSH keys:"
fi

ls -l $PRIVKEY
ls -l $PUBKEY
echo "Done."
echo

echo "##########################################################"
echo "# 17. Create crontab entries for automated data collection"
echo "##########################################################"
TODAY=`date +'%Y%m%d'`
if [ -f ../backup/$TODAY-crontab.backup ]; then
   echo "Found existing backup of /etc/crontab file:"
   ls -l ../backup/$TODAY-crontab.backup
else
   echo "Create new backup of current /etc/crontab file:"
   cp /etc/crontab ../backup/$TODAY-crontab.backup
   ls -l ../backup/$TODAY-crontab.backup
fi
echo

GREP=`grep $HOMEDIR/bin/send-data.sh /etc/crontab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/crontab"
   LINE2="# pi-weather: Get sensor data in 1-min intervals, + upload"
   sudo sh -c "echo \"$LINE2\" >> /etc/crontab"
   LINE3="*  *    * * *   pi      $HOMEDIR/bin/send-data.sh > $HOMEDIR/var/send-data.log 2>&1"
   sudo sh -c "echo \"$LINE3\" >> /etc/crontab"
   echo "Adding 3 lines to /etc/crontab file:"
   tail -4 /etc/crontab
else
   echo "Found send-data.sh line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 18. Create crontab entries for automated image archiving"
echo "##########################################################"
STIME=${MYCONFIG[wcam-img-stime]}
ETIME=${MYCONFIG[wcam-img-etime]}
RETEN=${MYCONFIG[wcam-img-reten]}

GREP=`grep $HOMEDIR/bin/wcam-archive /etc/crontab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/crontab"
   LINE2="# pi-weather: Archive webcam pics taken in 1-min intervals"
   sudo sh -c "echo \"$LINE2\" >> /etc/crontab"
   LINE3="*  *    * * *   pi      $HOMEDIR/bin/wcam-archive -i $HOMEDIR/var/raspicam.jpg -d $HOMEDIR/web/wcam -s $STIME -e $ETIME -r $RETEN >/dev/null 2>&1"
   sudo sh -c "echo \"$LINE3\" >> /etc/crontab"
   echo "Adding 3 lines to /etc/crontab file:"
   tail -4 /etc/crontab
else
   echo "Found wcam-archive line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 19. Create crontab entries for RRD DB and graph updates"
echo "##########################################################"

GREP=`grep $HOMEDIR/bin/rrdupdate.sh /etc/crontab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/crontab"
   LINE2="# pi-weather: Updates RRD DB and graphs in 1-min intervals"
   sudo sh -c "echo \"$LINE2\" >> /etc/crontab"
   LINE3="*  *    * * *   pi      $HOMEDIR/bin/rrdupdate.sh > $HOMEDIR/var/rrdupdate.log 2>&1"
   sudo sh -c "echo \"$LINE3\" >> /etc/crontab"
   echo "Adding 3 lines to /etc/crontab file:"
   tail -4 /etc/crontab
else
   echo "Found rrdupdate.sh line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 20. Create crontab entry for dayly time sync with rdate"
echo "##########################################################"

GREP=`grep /usr/sbin/rdate /etc/crontab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/crontab"
   LINE2="# pi-weather: Synchronize time daily at midnight"
   sudo sh -c "echo \"$LINE2\" >> /etc/crontab"
   LINE3="0  0    * * *   root    /usr/bin/rdate -4ns pool.ntp.org"
   sudo sh -c "echo \"$LINE3\" >> /etc/crontab"
   echo "Adding 3 lines to /etc/crontab file:"
   tail -4 /etc/crontab
else
   echo "Found rrdupdate.sh line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 21. Turn off crontab logging, reduce syslog noise level"
echo "##########################################################"

GREP=`grep 'EXTRA_OPTS=\"-L 0\"' /etc/default/cron`
if [[ $? > 0 ]]; then
   LINE1="# pi-weather: Turn off cron logs to syslog"
   sudo sh -c "echo \"$LINE1\" >> /etc/default/cron"
   LINE2="EXTRA_OPTS=\"-L 0\""
   sudo sh -c "echo \"$LINE2\" >> /etc/default/cron"
   echo "Adding 2 lines to /etc/default/cron file:"
   tail -3 /etc/default/cron
   echo
   echo "Restarting cron service:"
   sudo /etc/init.d/cron restart
else
   echo "Found EXTRA_OPTS line in /etc/default/cron file:"
   echo "$GREP"
fi
echo

# 2018 added for Debian Stretch based Raspbian
GREP=`grep -e '^LogLevel=' /etc/systemd/system.conf`
if [[ $? > 0 ]]; then
   LINE3="# pi-weather: Turn off systemd log noise to syslog"
   sudo sh -c "echo \"$LINE3\" >> /etc/systemd/system.conf"
   LINE4="LogLevel=warning"
   sudo sh -c "echo \"$LINE4\" >> /etc/systemd/system.conf"
   echo "Adding 2 lines to /etc/systemd/system.conf file:"
   tail -3 /etc/systemd/system.conf
fi
echo

if [[ -d /etc/rsyslog.d ]]; then
   echo "Install/overwrite systemd log noise reduction file:"
   echo "sudo cp ./no-systemd-noise.conf /etc/rsyslog.d"
   sudo cp ./no-systemd-noise.conf /etc/rsyslog.d
   ls -l /etc/rsyslog.d/no-systemd-noise.conf
fi
echo

echo "Done."
echo

echo "##########################################################"
echo "# 22. Setting local hostname to Station ID pi-weather-sid"
echo "##########################################################"
SID=${MYCONFIG[pi-weather-sid]}

GREP=`grep "$SID" /etc/hostname`
if [[ $? > 0 ]]; then
   sudo sh -c "echo $SID > /etc/hostname"
   echo "Updated $SID in /etc/hostname"
else
   echo "Found $SID line in /etc/hostname file:"
   echo "$GREP"
fi

GREP=`egrep '127\.0\.1\.1.*$SID' /etc/hosts`
if [[ $? > 0 ]]; then
   sudo sh -c "sed -i -e 's/127\.0\.1\.1.*/127\.0\.1\.1       $SID/' /etc/hosts"
   echo "Updated $SID in /etc/hosts"
else
   echo "Found $SID line in /etc/hosts file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 23. Configuring local web server for data visualization"
echo "##########################################################"
SID=${MYCONFIG[pi-weather-sid]}

GREP=`grep "$HOMEDIR" /etc/lighttpd/lighttpd.conf`
if [[ $? > 0 ]]; then
   sudo sh -c "sed -i -e 's/= \"\/var\/www\/html\"/= \"\/home\/pi\/$SID\/web\"/' /etc/lighttpd/lighttpd.conf"
else
   echo "Found HOMEDIR line in /etc/lighttpd/lighttpd.conf file:"
   echo "$GREP"
fi

sudo lighty-enable-mod fastcgi
sudo lighty-enable-mod fastcgi-php
sudo systemctl restart lighttpd

echo "Done."
echo

echo "##########################################################"
echo "# 24. Installing local web server documents and images"
echo "##########################################################"
for img in ../web/img/*; do
   fbname=$(basename "$img")
   echo "cp $img $HOMEDIR/web/images"
   cp $img $HOMEDIR/web/images
   echo "chmod 644 $HOMEDIR/web/images/$fbname"
   chmod 644 $HOMEDIR/web/images/$fbname
done
echo "cp ../web/style.css $HOMEDIR/web"
cp ../web/style.css $HOMEDIR/web
echo "chmod 644 $HOMEDIR/web/style.css"
chmod 644 $HOMEDIR/web/style.css

echo "cp ../web/vmenu.tm $HOMEDIR/web"
cp ../web/vmenu.htm $HOMEDIR/web
echo "chmod 644 $HOMEDIR/web/vmenu.htm"
chmod 644 $HOMEDIR/web/vmenu.htm

echo "cp ../web/index.php $HOMEDIR/web"
cp ../web/index.php $HOMEDIR/web
echo "chmod 644 $HOMEDIR/web/index.php"
chmod 644 $HOMEDIR/web/index.php

echo "cp ../web/showlog.php $HOMEDIR/web"
cp ../web/showlog.php $HOMEDIR/web
echo "chmod 644 $HOMEDIR/web/showlog.php"
chmod 644 $HOMEDIR/web/showlog.php

echo "creating $HOMEDIR/web/phpinfo.php"
echo "<?php phpinfo(); ?>" >  $HOMEDIR/web/phpinfo.php
chmod 644 $HOMEDIR/web/phpinfo.php

echo "Done."
echo

echo "##########################################################"
echo "# 25. Create the SFTP batch files"
echo "##########################################################"
echo "Create the SFTP batch file for sensor data upload"
cat <<EOM >$HOMEDIR/etc/sftp-dat.bat
cd var
put $HOMEDIR/var/sensor.txt
put $HOMEDIR/var/raspicam.jpg raspicam.jpg.tmp
rename raspicam.jpg.tmp raspicam.jpg
put $HOMEDIR/var/backup.txt
put $HOMEDIR/var/raspidat.htm
quit
EOM

echo "Done."
echo

echo "Create the SFTP batch file for RRD XML backup upload"
cat <<EOM >$HOMEDIR/etc/sftp-xml.bat
cd var
put $HOMEDIR/var/rrdcopy.xml.gz rrdcopy.xml.gz.tmp
rename rrdcopy.xml.gz.tmp rrdcopy.xml.gz
quit
EOM

echo "Done."
echo

echo "Create the SFTP batch file for MP4 timelapse upload"
cat <<EOM >$HOMEDIR/etc/sftp-mp4.bat
cd var
put $HOMEDIR/var/yesterday.mp4 yesterday.mp4.tmp
rename yesterday.mp4.tmp yesterday.mp4
quit
EOM

echo "Done."
echo

echo "Create the daymimax/momimax.htm SFTP batch file"
cat <<EOM >$HOMEDIR/etc/sftp-htm.bat
cd var
put $HOMEDIR/var/daymimax.htm daymimax.htm.tmp
put $HOMEDIR/var/momimax.htm momimax.htm.tmp
put $HOMEDIR/var/yearmimax.htm yearmimax.htm.tmp
rename daymimax.htm.tmp daymimax.htm
rename momimax.htm.tmp momimax.htm
rename yearmimax.htm.tmp yearmimax.htm
quit
EOM

echo "Done."
echo

echo "##########################################################"
echo "# 26. Create crontab entry for daily MP4 file creation"
echo "##########################################################"

GREP=`grep $HOMEDIR/bin/wcam-mkmovie /etc/crontab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/crontab"
   LINE2="# pi-weather: Generate the daily MP4 timelapse file"
   sudo sh -c "echo \"$LINE2\" >> /etc/crontab"
   LINE3="10 0    * * *   pi      $HOMEDIR/bin/wcam-mkmovie -a $HOMEDIR/web/wcam -o $HOMEDIR/var/yesterday.mp4 -v > $HOMEDIR/log/wcam-mkmovie.log 2>&1"
   sudo sh -c "echo \"$LINE3\" >> /etc/crontab"
   echo "Adding 3 lines to /etc/crontab file:"
   tail -4 /etc/crontab
else
   echo "Found wcam-mkmovie line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 27. Create crontab entry for RRD XML and MP4 file upload"
echo "##########################################################"

GREP=`grep $HOMEDIR/bin/send-night.sh /etc/crontab`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/crontab"
   LINE2="# pi-weather: Upload RRD XML backup and MP4 timelapse file"
   sudo sh -c "echo \"$LINE2\" >> /etc/crontab"
   LINE3="30 0    * * *   pi      $HOMEDIR/bin/send-night.sh > $HOMEDIR/log/send-night.log 2>&1"
   sudo sh -c "echo \"$LINE3\" >> /etc/crontab"
   echo "Adding 3 lines to /etc/crontab file:"
   tail -4 /etc/crontab
else
   echo "Found send-night.sh line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 28. Power saving: disable HDMI, PWR and ACT LED lights"
echo "##########################################################"
./powersave.sh
echo "./powersave.sh returned [$?]"

if [[ $? > 0 ]]; then
   echo "Error - powersave.sh failed" >&2
fi
echo "Done."
echo

echo "##########################################################"
echo "# 29. Disable IPv6 protocol support"
echo "##########################################################"
./disable-ipv6.sh
echo "./disable-ipv6.sh returned [$?]"

if [[ $? > 0 ]]; then
   echo "Error - disable-ipv6.sh failed" >&2
fi
echo "Done."
echo

echo "##########################################################"
echo "# 30. Configure 1st sensor read straight after boot"
echo "##########################################################"
GREP=`grep $HOMEDIR/bin/getsensor /etc/rc.local`
if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/rc.local"
   LINE2="# pi-weather: query the sensor after boot asap because the"
   sudo sh -c "echo \"$LINE2\" >> /etc/rc.local"
   LINE3="# 1st sensor readout is always off and handled as outlier."
   sudo sh -c "echo \"$LINE3\" >> /etc/rc.local"
   LINE4="$HOMEDIR/bin/getsensor -t bme280 -a 0x76"
   sudo sh -c "echo \"$LINE4\" >> /etc/rc.local"
   echo "Adding 4 lines to /etc/rc.local file:"
   tail -5 /etc/rc.local
else
   echo "Found $HOMEDIR/bin/getsensor line in /etc/rc.local file:"
   echo "$GREP"
fi

echo "##########################################################"
echo "# End of Pi-Weather Installation. Review script output and"
echo "# please reboot the system to enable all changes. COMPLETE"
echo "##########################################################"
