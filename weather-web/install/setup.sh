#!/bin/bash
##########################################################
# setup.sh 20170624 Frank4DD
#
# This script installs the pre-requsite software packages
# that are needed to compile the "pi-weather" server-side
# programs, creates the web and data folder structures.
#
# It is the first script to be run after downloading or
# cloning the git package. Before running it, copy the
# file etc/pi-web.templ to etc/pi-web.conf and edit
# its content to adjust configuration parameters.
#
# The script must be run as root, it will set ownership
# if needed.
#
# This script only installs the framework, individual 
# weather stations are onboarded with "newstation.sh"
# which is located in src, copied to the bin directory.
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
echo "# 2. Check if this script runs as user root."
echo "##########################################################"
if (( $EUID != 0 )); then
   echo "This script must be run as user \"root\"."
   exit 1;
fi

echo "Done."
echo

echo "##########################################################"
echo "# 3. Before we get SW packages, refresh the SW catalogue"
echo "##########################################################"
EXECUTE="apt-get update"
echo "Updating SW catalogue through [$EXECUTE]. Please wait approx 60s"
#$EXECUTE | grep Reading
# `$EXECUTE > /dev/null 2&>1`
echo "Done."
echo

echo "##########################################################"
echo "# 4. Install the RRD database tools and development files"
echo "##########################################################"
APPLIST="rrdtool librrd8 librrd-dev"
EXECUTE="apt-get install $APPLIST -y -q"
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
echo "# 5. Add transfer & image tools: openssh-sftp-server, zip"
echo "##########################################################"
APPLIST="openssh-sftp-server ffmpeg zip"
EXECUTE="apt-get install $APPLIST -y -q"
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
echo "# 6. Create the app/data directory and subfolder structure"
echo "##########################################################"
DATADIR=${MYCONFIG[pi-web-data]}
if [[ ! -d $DATADIR ]]; then
   echo "Create application directory [$DATADIR]"
   mkdir $DATADIR
   echo "Create sub-directory [$DATADIR/bin]"
   mkdir $DATADIR/bin
   echo "Create sub-directory [$DATADIR/chroot]"
   mkdir $DATADIR/chroot
   echo "Create sub-directory [$DATADIR/log]"
   mkdir $DATADIR/log
   echo "Create sub-directory [$DATADIR/etc]"
   mkdir $DATADIR/etc
else
   echo "Skipping creation, application directory [$DATADIR] exists."
fi
echo "Done."
echo

echo "##########################################################"
echo "# 7. Create the app/data directory and subfolder structure"
echo "##########################################################"
HTMLDIR=${MYCONFIG[pi-web-html]}
if [[ ! -d $HTMLDIR ]]; then
   echo "Create sub-directory [$HTMLDIR/web]"
   mkdir $HTMLDIR/web
   echo "Create sub-directory [$HTMLDIR/web/images]"
   mkdir $HTMLDIR/web/images
else
   echo "Skipping creation, web root directory [$HTMLDIR] exists."
fi
echo "Done."
echo

echo "##########################################################"
echo "# 8. SSH setup: create new group 'rssh' with gid 200"
echo "##########################################################"
# we don't yet check if there is already a group with GID 200!!
LINE1="rssh:x:200:"

GREP=`grep 'rssh:x:200:' /etc/group`
if [[ $? > 0 ]]; then
   echo $LINE1 >> /etc/group
   echo "Adding 1 line to /etc/group file:"
   tail -3 /etc/group
else
   echo "Found line [$LINE1] in /etc/group file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 9. rssh setup: create configuration file /etc/rssh.conf"
echo "##########################################################"
SSHDCONF=/tmp/ssh1.conf
SFTPCONF=/tmp/ssh2.conf

echo "tail -6 /etc/ssh/sshd_config > $SSHDCONF"
tail -6 /etc/ssh/sshd_config > $SSHDCONF


cat <<EOM >$SFTPCONF
Match Group rssh
        ChrootDirectory /srv/app/pi-web01/chroot/%u
        ForceCommand internal-sftp
        PasswordAuthentication yes
        X11Forwarding no
        AllowTcpForwarding no
EOM

DIFF=`diff $SSHDCONF $SFTPCONF`
if  [[ $? > 0 ]]; then
   echo "Updating /etc/ssh/sshd_config"
   echo "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig"
   cp cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
   cat <<EOM >>/etc/ssh/sshd_config
Match Group rssh
        ChrootDirectory /srv/app/pi-web01/chroot/%u
        ForceCommand internal-sftp
        PasswordAuthentication yes
        X11Forwarding no
        AllowTcpForwarding no
EOM
   echo
   echo "tail -6 /etc/ssh/sshd_config"
   tail -6 /etc/ssh/sshd_config
   echo
   echo "service ssh restart"
   service ssh restart
else
   echo "Found matching lines in /etc/ssh/sshd_config:"
   echo "tail -6 /etc/ssh/sshd_config"
   tail -6 /etc/ssh/sshd_config
fi

echo "Done."
echo

echo "##########################################################"
echo "# 10. Set rssh logging to $DATADIR/log/pi-web01.log"
echo "##########################################################"
LOGFILE=$DATADIR/log/pi-web01.log

GREP=`grep $LOGFILE /etc/rsyslog.conf`
if [[ $? > 0 ]]; then
   LINE1="local0.*                        $DATADIR/log/pi-web01.log"
   echo "Adding [$LINE1] to /etc/rsyslog.conf file:"
   echo "$LINE1" >> /etc/rsyslog.conf
   tail -3 /etc/rsyslog.conf
   echo
   echo "Restarting syslog service: service rsyslog restart"
   service rsyslog restart
else
   echo "Found line [$LOGFILE] in /etc/rsyslog.conf file:"
   echo "$GREP"
fi

echo "##########################################################"
echo "# 11. Compile 'C' source code in ../src"
echo "##########################################################"
cd ../src
echo "Cleanup any old binaries in src: make clean"
make clean
echo
echo "Compile new binaries in src: make"
make
echo

echo "##########################################################"
echo "# 12. Install programs and scripts to $DATADIR/bin"
echo "##########################################################"
export BINDIR=$DATADIR/bin
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
echo "# 13. Copy the "pi-web.conf" file to $DATADIR/etc"
echo "##########################################################"
CONFIG="../etc/pi-web.conf"
if [[ ! -f $CONFIG ]]; then
   echo "Error - cannot find config file [$CONFIG]" >&2
   exit 1
fi

if [[ -f $DATADIR/etc/pi-web.conf ]]; then
   echo "Skipping configuration file copy, $DATADIR/etc/pi-web.conf exists."
else
   echo "cp $CONFIG $DATADIR/etc"
   cp $CONFIG $DATADIR/etc
   chmod 644 $DATADIR/etc/pi-web.conf
fi
ls -l $DATADIR/etc/pi-web.conf
echo "Done."
echo

echo "##########################################################"
echo "# 14. Create crontab entries for RRD DB and graph updates"
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

GREP=`grep $DATADIR/bin/rrdupdate.sh /etc/crontab`
if [[ $? > 0 ]]; then
#   LINE1="##########################################################"
#   echo "$LINE1" >> /etc/crontab
#   LINE2="# pi-weather: Get sensor data in 1-min intervals, + upload"
#   echo "$LINE2" >> /etc/crontab
#   LINE3="*  *    * * *   pi      $DATADIR/bin/rrdupdate.sh > $DATADIR/log/rrdupdate.log 2>&1"
#   echo "$LINE3" >> /etc/crontab
#   echo "Adding 3 lines to /etc/crontab file:"
   echo "This update is needed, but currently commented out!"
   echo "Crontab entries are set for each station, see newstation.sh"
   tail -4 /etc/crontab
else
   echo "Found rrdupdate.sh line in /etc/crontab file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 15. Turn off crontab logging, reduce syslog noise level"
echo "##########################################################"

GREP=`grep 'EXTRA_OPTS=\"-L 0\"' /etc/default/cron`
if [[ $? > 0 ]]; then
   LINE1="# pi-weather: Turn off cron logs to syslog"
   echo "$LINE1" >> /etc/default/cron
   LINE2='EXTRA_OPTS="-L 0"'
   echo $LINE2 >> /etc/default/cron
   echo "Adding 2 lines to /etc/default/cron file:"
   tail -3 /etc/default/cron
   echo
   echo "Restarting cron service:"
   service cron restart
else
   echo "Found EXTRA_OPTS line in /etc/default/cron file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 16. Installing local web server documents and images"
echo "##########################################################"
for img in ../web/img/*; do
   fbname=$(basename "$img")
   echo "cp $img $HTMLDIR/images"
   cp $img $HTMLDIR/images
   echo "chmod 644 $HTMLDIR/images/$fbname"
   chmod 644 $HTMLDIR/images/$fbname
done
echo "cp ../web/style.css $HTMLDIR"
cp ../web/style.css $HTMLDIR
echo "chmod 644 $HTMLDIR/style.css"
chmod 644 $HTMLDIR/style.css

echo "cp ../web/index.php $HTMLDIR"
cp ../web/index.php $HTMLDIR
echo "chmod 644 $HTMLDIR/index.php"
chmod 644 $HTMLDIR/index.php

echo "cp ../web/ol.* $HTMLDIR"
cp ../web/ol.* $HTMLDIR
echo "chmod 644 $HTMLDIR/ol.*"
chmod 644 $HTMLDIR/ol.*

echo "creating $HTMLDIR/phpinfo.php"
echo "<?php phpinfo(); ?>" >  $HTMLDIR/phpinfo.php
chmod 644 $HTMLDIR/phpinfo.php

echo "Done."
echo

echo "##########################################################"
echo "# 17. Create common.php, e.g. include to station index.php"
echo "##########################################################"
COMMONPHP="$HTMLDIR/common.php"

if [[ ! -f $COMMONPHP ]]; then
   cat <<EOM >$COMMONPHP
<?php
// get pi-weather config data
function loadConfig(\$station) {
   \$datapath = "$DATADIR";          // Set once by setup script
   \$confpath = \$datapath."/chroot/".\$station."/etc/".\$station.".conf";

   ini_set("auto_detect_line_endings", true);
   \$conf = array();
   \$fh = fopen(\$confpath, "r");
   while (\$line=fgets(\$fh, 80)) {
      if((! preg_match('/^#/', \$line)) &&    // show only lines w/o #
         (! preg_match('/^$/', \$line))) {    // and who are not empty
         \$line_a = explode("=", \$line);      // explode at the '=' sign
         \$conf[\$line_a[0]] = \$line_a[1];     // assign key/values
      }
   }
   return \$conf;
}
?>
EOM

   echo "chmod 644 $HTMLDIR/common.php"
   chmod 644 $HTMLDIR/common.php
else
   echo "Skipping creation, file $COMMONPHP exists."
fi

echo "Done."
echo


echo "##########################################################"
echo "# End of Pi-Weather Installation."
echo "##########################################################"
