#!/bin/bash
##########################################################
# backup.sh 20170226 Frank4DD
#
# This script backs up the local directories containing
# configuration, apps and raspi data in /etc, /boot
# and /home. It puts the backup archive into a locally
# mounted USB stick:
# /dev/sda1       7.2G  4.0K  7.2G   1% /backup
#
# Backup success is logged via logger to syslog.
# Backups run via cron on a once-per-week schedule.
##########################################################
# set debug: 0=off 1=normal  2=verbose
DEBUG=0

##########################################################
# binaries location
##########################################################
TAR="/bin/tar"
DATE="/bin/date"
HNAME="/bin/hostname"
LOGGER="/usr/bin/logger"
DPKG="/usr/bin/dpkg"
BINARIES="$TAR $DATE $HNAME $LOGGER $DPKG"

##########################################################
# define the local directories we want to have in backup
##########################################################
ARCH_TEMP=`mktemp -d -p /backup`
ARCH_DIRS="/etc /boot /home"

##########################################################
# define local directories we want to exclude from above
##########################################################
EXCLUDE="/home/pi/pi-ws*/web/wcam"

##########################################################
# define the backup destination directory on the USB stick
##########################################################
DEST_DIR="/backup"

##########################################################
############# function definitions #######################
##########################################################

##########################################################
# TIMESTAMP contains current time, i.e. "20161211-1014"
##########################################################
TIMESTAMP=`$DATE +"%Y%m%d_%H%M"`

##########################################################
# ARCH_NAME is the backup name based on hostname and time
# i.e. raspi2-system-20161211-1014.tar.gz
##########################################################
ARCH_NAME=`$HNAME`-system-$TIMESTAMP.tar.gz

##########################################################
# PACKET_LIST is the name of the file storing the list of
# installed OS packages
##########################################################
PACKET_LIST=`$HNAME`-syspkg-$TIMESTAMP.txt

##########################################################
# function check_binaries and check_dirs
##########################################################
CHECK_BINARIES() {
for BIN in $BINARIES; do
  if [ $DEBUG == "2" ]; then echo "CHECK_BINARIES(): $BIN"; fi
  [ ! -x $BIN ] && { echo "$BIN not found, exiting."; exit -1; }
done
}

CHECK_DIRS() {
  ALLDIRS="$ARCH_DIRS $ARCH_TEMP $DEST_DIR"
  for DIR in $ALLDIRS; do
    if [ $DEBUG == "2" ]; then echo "CHECK_DIRS(): $DIR"; fi
    [ ! -x $DIR ] && { echo "$DIR not found, exiting."; exit -1; }
    done
}

##########################################################
# function generate_packetlist
# Pkgs can be restored with: dpkg --clear-selections
# sudo dpkg --set-selections < list.txt
##########################################################
GENERATE_PACKETLIST() {

  EXECUTE="$DPKG --get-selections > $ARCH_TEMP/$PACKET_LIST"

  if [ $DEBUG == "2" ]; then echo $EXECUTE; fi
  `eval $EXECUTE`

  RC=$?
  if [ $RC -ne 0 ]; then
    $LOGGER -p user.info $ADD_STDERR "backup.sh: packet list generation failed with return code $RC."
  else
    $LOGGER -p user.info $ADD_STDERR "backup.sh: generated new packet list in $ARCH_TEMP/$PACKET_LIST."
  fi
}

##########################################################
# function create_archive
##########################################################
CREATE_ARCHIVE() {
  ARCHIVE_SIZE=0

  EXECUTE="$TAR cfpz $ARCH_TEMP/$ARCH_NAME --exclude=$EXCLUDE $ARCH_DIRS"

  if [ $DEBUG == "2" ]; then echo $EXECUTE; fi

  `$EXECUTE 2&>/dev/null`

  # Unfortunately, tar return codes are almost meaningless. See:
  # http://www.gnu.org/software/tar/manual/html_node/tar_34.html
  # Well, we pick it up and report on any "unusual" return codes.
  RC=$?
  if [ $RC -ne 0 ] && [ $RC -ne 2 ]; then
    $LOGGER -p user.info $ADD_STDERR "backup.sh: tar failed with return code $RC."
  else
    ARCHIVE_SIZE=`du -h $ARCH_TEMP/$ARCH_NAME | cut -f 1,1`
  fi

  $LOGGER -p user.info $ADD_STDERR "backup.sh: Created $ARCHIVE_SIZE archive $ARCH_TEMP/$ARCH_NAME."
}

##########################################################
# function transfer_archive (scp or mv)
##########################################################
TRANSFER_ARCHIVE() {
#  EXECUTE1="$SCP -q -c blowfish -i $SCP_KEY $ARCH_TEMP/$ARCH_NAME $DEST_USER@$DEST_IP:$DEST_DIR/$ARCH_NAME.tmp"
#  EXECUTE2="$SSH -q -c blowfish -i $SCP_KEY $DEST_USER@$DEST_IP /bin/mv $DEST_DIR/$ARCH_NAME.tmp $DEST_DIR/$ARCH_NAME"
  EXECUTE1="/bin/mv $ARCH_TEMP/$PACKET_LIST $DEST_DIR/$PACKET_LIST"
  EXECUTE2="/bin/mv $ARCH_TEMP/$ARCH_NAME $DEST_DIR/$ARCH_NAME"

  if [ $DEBUG == "2" ]; then echo $EXECUTE1; fi
  `$EXECUTE1`

  RC=$?
  if [ $RC -ne 0 ]; then
    $LOGGER -p user.info $ADD_STDERR "backup.sh: $PACKET_LIST mv from $ARCH_TEMP failed with return code $RC."
  else
    if [ $DEBUG == "2" ]; then echo $EXECUTE2; fi
    `$EXECUTE2`
    if [ $RC -ne 0 ]; then
        $LOGGER -p user.info $ADD_STDERR "backup.sh: $ARCH_NAME mv from $ARCH_TEMP failed with return code $RC."
    fi
  fi

  $LOGGER -p user.info $ADD_STDERR "backup.sh: Moved archive files to $DEST_DIR."
}

##########################################################
# function cleanup_tempdir removes remainders
##########################################################
CLEANUP_TEMPDIR() {
  FILELIST=`ls $ARCH_TEMP/*-system-* 2>/dev/null`
  EXECUTE="/bin/rm $FILELIST"

  for FILE in $FILELIST; do
    /bin/rm $FILE
    if [ $DEBUG == "2" ]; then echo "Clean up temp: rm $FILE"; fi
  done
  rmdir $ARCH_TEMP
}

##########################################################
################# MAIN ###################################
##########################################################
if [ $DEBUG == "2" ]; then ADD_STDERR="-s"; fi

# check if the binaries and dirs are there
CHECK_BINARIES

CHECK_DIRS

$LOGGER -p user.info $ADD_STDERR "backup.sh: Start backup job."

GENERATE_PACKETLIST

CREATE_ARCHIVE

TRANSFER_ARCHIVE

CLEANUP_TEMPDIR

$LOGGER -p user.info $ADD_STDERR "backup.sh: Finished backup job."
################# END of MAIN #############################
