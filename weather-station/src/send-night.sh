#!/bin/bash
##########################################################
# send-night.sh 20170624 Frank4DD
#
# This script runs daily after midnight, sending two
# files to the Internet server:
#       1. RRD database XML export    -> var/rrdcopy.xml
#       2. daily MP4 timelapse movie  -> var/yesterday.mp4
#
# Please set config file path to your installations value!
##########################################################
echo "send-night.sh: Run at `date`"
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null
CONFIG=$SCRIPTPATH/../etc/pi-weather.conf
echo "send-night.sh: using $CONFIG"

##########################################################
# readconfig() function to read the config file variables
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

##########################################################
# Check for the config file, and source it
##########################################################
if [[ ! -f $CONFIG ]]; then
  echo "send-data.sh: Error - cannot find config file [$CONFIG]" >&2
  exit -1
fi
readconfig MYCONFIG < "$CONFIG"

WHOME=${MYCONFIG[pi-weather-dir]}
STATION=${MYCONFIG[pi-weather-sid]}

##########################################################
# Create a database export into $WSHOME/var/rrdcopy.xml.gz
# Sends a nightly DB for import on the Internet server,
# its import there clears out upload gaps should the exist
##########################################################
if [ -f $WHOME/var/rrdcopy.xml.gz ]; then
   echo "`date`: Deleting old file $WHOME/var/rrdcopy.xml.gz"
   rm $WHOME/var/rrdcopy.xml.gz
fi

echo "`date`: Creating new XML export into $WHOME/var/rrdcopy.xml"
rrdtool dump $WHOME/rrd/weather.rrd $WHOME/var/rrdcopy.xml
echo "`date`: Compressing XML export file $WHOME/var/rrdcopy.xml"
gzip $WHOME/var/rrdcopy.xml

##########################################################
# Upload xml DB archive /tmp/rrdcopy.xml.gz to the server
##########################################################
SFTPDEST=$STATION@${MYCONFIG[pi-weather-sftp]}

if [ -f $WHOME/var/rrdcopy.xml.gz ]; then
   echo "`date`: Uploading XML export file to $SFTPDEST"
   /usr/bin/sftp -b $WHOME/etc/sftp-xml.bat $SFTPDEST
else
   echo "`date`: No upload, can't find $WHOME/var/rrdcopy.xml.gz"
fi

##########################################################
# Upload the daily movie /tmp/yesterday.mp4 to the server
##########################################################
if [ -f $WHOME/var/yesterday.mp4 ]; then
   echo "`date`: Uploading daily movie file to $SFTPDEST"
   /usr/bin/sftp -b $WHOME/etc/sftp-mp4.bat $SFTPDEST
   echo "`date`: Deleting file $WHOME/var/yesterday.mp4"
   rm $WHOME/var/yesterday.mp4
else
   echo "`date`: No MP4 upload, can't find $WHOME/var/yesterday.mp4"
fi

##########################################################
# Upload the daily daymimax/momimax.htm tables to server
##########################################################
if [ ! -f $WHOME/var/yearmimax.htm ]; then
   $WHOME/bin/momimax -s $WHOME/rrd/weather.rrd -y $WHOME/var/yearmimax.htm
   echo "`date`: Created $WHOME/var/yearmimax.htm"
fi

if [ ! -f $WHOME/var/momimax.htm ]; then
   $WHOME/bin/momimax -s $WHOME/rrd/weather.rrd -m $WHOME/var/momimax.htm
   echo "`date`: Created $WHOME/var/momimax.htm"
fi

if [ ! -f $WHOME/var/daymimax.htm ]; then
   $WHOME/bin/momimax -s $WHOME/rrd/weather.rrd -d $WHOME/var/daymimax.htm
   echo "`date`: Created $WHOME/var/daymimax.htm"
fi

if [ -f $WHOME/var/daymimax.htm ]\
   || [ -f $WHOME/var/momimax.htm ]\
   || [ -f $WHOME/var/yearmimax.htm ]; then
   echo "`date`: Uploading daymimax/momimax/yearmimax to $SFTPDEST"
   /usr/bin/sftp -b $WHOME/etc/sftp-htm.bat $SFTPDEST
   echo "`date`: Deleting daymimax/momimax/yearmimax.htm in $WHOME/var"
   rm $WHOME/var/daymimax.htm
   rm $WHOME/var/momimax.htm
   rm $WHOME/var/yearmimax.htm
else
   echo "`date`: Can't find daymimax/momimax/yearmimax.htm in $WHOME/var"
fi
echo "send-night.sh: Finished `date`"
############# end of send-night.sh ########################
