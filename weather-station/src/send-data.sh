#!/bin/bash
##########################################################
# send-data.sh 20170624 Frank4DD
#
# This script runs in 1-min intervals through cron.
# It has the following 4 tasks:
# 	1. Read the sensor data   -> var/sensor.txt
#                                 -> var/backup.txt
# 	2. Save the webcam image  -> var/raspicam.jpg
# 	3. Collect system data    -> var/raspidat.htm
#	4. Internet server upload -> weather.fm4dd.com
#
# Please set config file path to your installations value!
##########################################################
sleep 5	# run 5sec past 00, avoid collision w old script
echo "send-data.sh: Run at `date`"
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null
CONFIG=$SCRIPTPATH/../etc/pi-weather.conf
echo "send-data.sh: using $CONFIG"

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
# 1. Take the sensor reading, save it to txt for Internet
# server upload, and save it to html for the local webpage.
# Also create a backup file with the last 60 readings, to
# be used in case of short network outages (up to one hour).
##########################################################
STYPE=${MYCONFIG[sensor-type]}     # e.g. bme280, am2302
SADDR=${MYCONFIG[sensor-addr]}     # i2c sensor address
TCALI=${MYCONFIG[pi-weather-tcal]} # temp correction
PCALI=${MYCONFIG[pi-weather-pcal]} # bmpr correction
HCALI=${MYCONFIG[pi-weather-hcal]} # humi correction

echo "send-data.sh: Getting sensor data for $STYPE $SADDR";
if [ "$STYPE" == "bme280" ]; then
   EXECUTE="$WHOME/bin/getsensor -t $STYPE -a $SADDR -b $PCALI -c $TCALI -d $HCALI -j $WHOME/web/getsensor.json"
fi
if [ "$STYPE" == "am2302" ]; then
   GPIO=${MYCONFIG[sensor-gpio]}    # am2302/dht22 gpio pin number, e.g. 4
   EXECUTE="$WHOME/bin/getsensor -t $STYPE -a $SADDR -p $GPIO -b $PCALI -c $TCALI -d $HCALI -j $WHOME/web/getsensor.json"
fi
echo "send-data.sh: $EXECUTE";
SENSORDATA=`$EXECUTE`
RET=$?
echo "send-data.sh: sensor data [$SENSORDATA]"
if [[ $RET == '0' && $SENSORDATA != "Error"* ]]; then
  echo $SENSORDATA > $WHOME/var/sensor.txt
else
  echo "send-data.sh: Error updating of $WHOME/var/sensor.txt"
fi


##########################################################
# Add newest data entry to bottom of the backup file.
# Manage file growth: delete first (oldest) line from file
##########################################################
echo  $SENSORDATA >> $WHOME/var/backup.txt;

LENGTH=`wc -l $WHOME/var/backup.txt | cut -d " " -f 1,1`
if [ $LENGTH -gt 60 ]; then
  sed --in-place '1d' $WHOME/var/backup.txt
fi

##########################################################
# 2. Check if we got a camera. If yes, take the webcam
# picture, save it to var/raspicam.jpg, and link a copy
# to web/raspicam.jpg
##########################################################
WCAMCHECK=`vcgencmd get_camera`;
if [ "$WCAMCHECK" == "supported=1 detected=1" ]; then
   raspistill -w 640 -h 480 -q 80 -o $WHOME/var/raspicam.jpg
   RET=$?
else
   echo "send-data.sh: Could not find camera: $WCAMCHECK"
fi

if [ $RET == 0 ]; then
   cp $WHOME/var/raspicam.jpg $WHOME/web/images/raspicam.jpg
   echo "send-data.sh: Created new webcam image:"
   ls -l $WHOME/var/raspicam.jpg
   ls -l $WHOME/web/images/raspicam.jpg
else
   echo "send-data.sh: Error executing raspistill command."
fi

##########################################################
# 3. Collect the stations performance data into htm file
##########################################################
# Get the station IP address, e.g. 192.168.179.244
HOSTIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
# Get the uptime, e.g. 19d:4h:17m:52s
UPTIME=`awk '{print int($1/86400)"d:"int($1%86400/3600)"h:"int(($1%3600)/60)"m:"int($1%60)"s"}' /proc/uptime`
# Get the CPU load in percent, e.g. 2%
CPULOAD=`top -bn 1 | awk 'NR>7{s+=$9} END {print s/4"%"}'`
# Get the memory usage, e.g. 726MB of 860MB
MEMUSED=`free | grep Mem | awk '{printf("%.0fM of %.0fM\n", $3/1024, $2/1024)}'`
# Get the disk usage, e.g. 32GB of 59GB
DISKUSED=`df -h | grep '/dev/root' | awk {'print $3 " of " $2'}`
CPUTEMP=`cat /sys/class/thermal/thermal_zone0/temp |  awk '{printf("%.2f°C\n", $1/1000)}'`

echo "send-data.sh: Updating $WHOME/var/raspidat.htm"

cat <<EOM >$WHOME/var/raspidat.htm
<table>
<tr><th>Station Uptime:</th></tr>
<tr><td>$UPTIME</td></tr>
<tr><th>IP Address:</th></tr>
<tr><td>$HOSTIP</td></tr>
<tr><th>CPU Usage:</th></tr>
<tr><td>$CPULOAD</td></tr>
<tr><th>RAM Usage:</th></tr>
<tr><td>$MEMUSED</td></tr>
<tr><th>Disk Usage:</th></tr>
<tr><td>$DISKUSED</td></tr>
<tr><th>CPU Temperature:</th></tr>
<tr><td>$CPUTEMP</td></tr>
</table>
EOM

##########################################################
# 4. Copy four files var/raspinet.txt, var/raspicam.jpg
# var/sensor.txt and var/backup.txt to the Internet server
##########################################################
if [ ${MYCONFIG[pi-weather-sftp]} == "none" ]; then
   echo "send-data.sh: pi-weather-sftp=none, remote data upload disabled."
   exit
fi

SFTPDEST=$STATION@${MYCONFIG[pi-weather-sftp]}

if [ -f $WHOME/etc/sftp-dat.bat ]; then
   echo "send-data.sh: Sending files to $SFTPDEST"
   sftp -q -b $WHOME/etc/sftp-dat.bat $SFTPDEST
else
   echo "send-data.sh: Cannot find $WHOME/etc/sftp-dat.bat"
fi
############# end of send-data.sh ########################
