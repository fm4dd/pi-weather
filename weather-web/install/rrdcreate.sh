#!/bin/bash
##########################################################
# rrdcreate.sh 20170810 Frank4DD
#
# This script creates the RRD database that will hold the
# weather data collected from sensors in 1-min intervals.
#
# On the server, the rrd DB is typically created through
# import from the weather stations initial data upload.
# In rare cases, the database can be re-created by running
# this script as root.
##########################################################
echo "rrdcreate.sh: Running at `date`"

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
echo "# 4. Check if the database folder exists - if not, exit"
echo "##########################################################"
RRD_DIR=${MYCONFIG[pi-web-data]}/chroot/$STATION/rrd

if [[ -d $RRD_DIR ]]; then
    echo "Using database directory $RRD_DIR."
else
   echo "Cannot find folder $RRD_DIR."
   exit 1
fi
echo "Done"
echo

echo "##########################################################"
echo "# 5. Check if the rrdtool database system is installed"
echo "##########################################################"
if ! [ -x "$(command -v rrdtool)" ]; then
  echo "Error - rrdtool is not installed." >&2
  exit -1
fi
echo "Done"
echo

echo "##########################################################"
echo "# 6. Check if the database already exists - if yes, backup"
echo "##########################################################"
RRD=$RRD_DIR/$STATION.rrd

if [[ -f $RRD ]]; then
  echo "RRD database [$RRD] exists"
  ls -l $RRD
  echo
  read -p "Are you sure to wipe $RRD [Y/N]? " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
  echo
  BACKUP=../backup/`date +%y%m%d-%H%M`-backup-`basename $RRD`
  echo "mv $RRD $BACKUP"
  #mv $RRD $BACKUP
fi

echo "Done"
echo

exit 0

##########################################################
# The RRD database will hold four data sources:
# ----------------------------------------------
# 1. Air temperature (in degree Celsius)
# 2. Relative humidity (in percent)
# 3. Barometric pressure (in Pascal, or hPa)
# 4. Daytime (sunrise..sunset) flag (0=day, 1=night)
#
# The data slots are allocated as follows:
# ----------------------------------------
# 1. store 1-min readings in 20160 entries (14 days: 60s*24hr*14d)
# RRA:AVERAGE:0.5:1:20160
# 2. store one 60min average in 17568 entries (2 years: 24hr*732d)
# RRA:AVERAGE:0.5:60:17568
# 3. store one day average in 7320 entries (20 years: 7320d)
# RRA:AVERAGE:0.5:1440:7320
#
# additionally, we store MIN and MAX values at the same intervals.
##########################################################

echo "##########################################################"
echo "# Creating RRD database [$RRD]."
echo "##########################################################"

EXECUTE="rrdtool create $RRD          \
--start now --step 60s       \
DS:temp:GAUGE:300:-100:100   \
DS:humi:GAUGE:300:0:100      \
DS:bmpr:GAUGE:300:0:200000   \
DS:dayt:GAUGE:300:0:1        \
RRA:AVERAGE:0.5:1:20160      \
RRA:AVERAGE:0.5:60:17568     \
RRA:AVERAGE:0.5:1440:7320    \
RRA:MIN:0.5:60:17568         \
RRA:MAX:0.5:60:17568         \
RRA:MIN:0.5:1440:7320        \
RRA:MAX:0.5:1440:7320"

echo $EXECUTE
echo
`$EXECUTE`

RET=0
if [[ -f $RRD ]]; then
  echo "Database [$RRD] created."
else
  echo "Could not create database [$RRD]."
  RET=1
fi

echo "Done"
echo
echo "rrdcreate.sh: Finished at `date`"
exit $RET
############# end of rrdcreate.sh ########################
