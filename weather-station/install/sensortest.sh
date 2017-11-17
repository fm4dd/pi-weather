#!/bin/bash
##########################################################
# sensortest.sh 20170624 Frank4DD
#
# This script tests various weather station functions,
# including sensors, and camera.
#
# It runs at installation time, and later if needed.
#
# Returns 0 on sucess, 1 for errors.
##########################################################
CONFIG="../etc/pi-weather.conf"
SUCCESS=0

echo "sensortest.sh: Testing pi-weather station functions"

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
echo "# Check for the config file, and source it"
echo "##########################################################"
if [[ ! -f $CONFIG ]]; then
  echo "sensortest.sh: Error - cannot find config file [$CONFIG]" >&2
  exit 1
fi

readconfig MYCONFIG < "$CONFIG"
STRLEN=${#MYCONFIG[@]}
echo "sensortest.sh: Reading file [$CONFIG] with [$STRLEN] values"
WHOME=${MYCONFIG[pi-weather-dir]}

echo "##########################################################"
echo "# Check if the I2C bus was enabled with raspi-config"
echo "##########################################################"
GREP=`grep "dtparam=i2c_arm=on" /boot/config.txt`
if [[ $? > 0 ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "ATTENTION: the I2C bus was not enabled with raspi-config!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
else
  echo "OK. I2C bus is enabled in /boot/config.txt: $GREP"
fi

echo "##########################################################"
echo "# Try reading temperature, humidity and pressure data"
echo "##########################################################"
STYPE=${MYCONFIG[sensor-type]}     # e.g. bme280, am2302
SADDR=${MYCONFIG[sensor-addr]}     # i2c sensor address
TCALI=${MYCONFIG[pi-weather-tcal]} # temp correction

if [ ! "$STYPE" == "bme280" ] && [ ! "$STYPE" == "am2302" ]; then
   echo "sensortest.sh: Error - invalid sensor type [$STYPE]" >&2
   SUCCESS=1
fi

if [ "$STYPE" == "bme280" ]; then
   echo "sensortest.sh: Getting sensor data for $STYPE $SADDR";
   EXECUTE="$WHOME/bin/getsensor -t $STYPE -a $SADDR -c $TCALI"
fi

if [[ ! -f ${MYCONFIG[pi-weather-dir]}/bin/getsensor ]]; then
   echo "sensortest.sh: Error - cannot find getsensor program" >&2
   SUCCESS=1
else
   echo "sensortest.sh: $EXECUTE"
   SENSORDATA=`$EXECUTE`
   RETURN=$?
fi

STRLEN=${#SENSORDATA}
echo "sensortest.sh: $SENSORDATA"
echo "sensortest.sh: Length of sensor data: $STRLEN"
echo "sensortest.sh: getsensor return code: $RETURN"

echo "##########################################################"
echo "# Check if the camera was enabled with raspi-config"
echo "##########################################################"
GREP=`grep "start_x=1" /boot/config.txt`
if [[ $? > 0 ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "ATTENTION: the camera was not enabled with raspi-config!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
else
  echo "OK. Camera is enabled in /boot/config.txt: $GREP"
fi

echo "##########################################################"
echo "# Check if we see the camera. If yes take a webcam picture"
echo "##########################################################"
WCAMCHECK=`vcgencmd get_camera`
WCAMFILE="/tmp/raspicam-check.jpg"

echo "sensortest.sh: Camera detection result: $WCAMCHECK"

if [ "$WCAMCHECK" == "supported=1 detected=1" ]; then
   echo "sensortest.sh: Creating new webcam test image $WCAMFILE"
   raspistill -w 640 -h 480 -q 80 -o /tmp/raspicam-check.jpg
else
   echo "sensortest.sh: Could not find camera: $WCAMCHECK"
   echo "sensortest.sh: pi-weather can operate without it."
fi

if [ -s $WCAMFILE ]; then
  WCAMSIZE=$(wc -c <"$WCAMFILE")
  echo "sensortest.sh: Webcam test image created, size: $WCAMSIZE bytes."
else
  echo "sensortest.sh: Error webcam test image does not exist, or is empty."
fi

echo "##########################################################"
if [ $SUCCESS -eq 0 ]; then
   echo "# sensortest.sh: pi-weather function test completed OK." 
else
   echo "# sensortest.sh: pi-weather function test complete with errors." 
fi
echo "##########################################################"

exit $SUCCESS
############# end of sensortest.sh ########################
