#!/bin/bash
##########################################################
# display.sh 20170930 Frank4DD
#
# This script is run via cron in 1-minute intervals. It
# connects with scp to the local Pi weather station and
# collects that latest sensor.txt plus the three daily_
# images containing the latest temperature, humidity and 
# pressure graphs.
#
# Before it begins, it decides if the TFT display needs
# to be on or off, based on the TSL2561 light sensor.
# Threshold is 1 lux.
#
# For management of the 20x4 character LCD display, a call
# to sensor.py is made, which drives the LCD ouput.
##########################################################
HOME="/home/pi/pi-display"

##########################################################
# Get the environment light data, return code from "lux"
##########################################################
$HOME/bin/lux
LUX=$?
echo "Brightness (Lux): $LUX"

##########################################################
# Get the current TFT display power state 
##########################################################
DISPLAY=`vcgencmd display_power`
echo "Display State: $DISPLAY"

##########################################################
# Call the 20x4 character LCD control program
##########################################################
python $HOME/bin/sensor.py

##########################################################
# If environmental light is low, turn off the TFT display
##########################################################
if [ $LUX -lt 1 ] && [ "$DISPLAY" == "display_power=1" ]; then
   vcgencmd display_power 0 > /dev/null
   echo "Start night mode, TFT display off"
   exit 0
fi

##########################################################
# If environmental light brightens, enable the TFT display
##########################################################
if [ $LUX -ge 1 ] && [ "$DISPLAY" == "display_power=0" ]; then
   vcgencmd display_power 1 > /dev/null
   echo "Start day mode, TFT display on"
   DISPLAY=`vcgencmd display_power`
fi

##########################################################
# If the TFT display is "on", get data and process images
##########################################################
if [ "$DISPLAY" == "display_power=1"  ]; then
   scp pi@192.168.179.244:/home/pi/pi-ws01/var/sensor.txt $HOME/var
   scp pi@192.168.179.244:/home/pi/pi-ws01/web/images/daily_*.png $HOME/var
   convert \( $HOME/var/daily_temp.png $HOME/var/daily_humi.png $HOME/var/daily_bmpr.png -append \) +append $HOME/var/out.png
   kill -HUP $(ps aux | grep '[f]bi' | awk '{print $2}')
   fbi --autozoom --noverbose -d /dev/fb0 --vt 1 $HOME/var/out.png
fi
##########################################################
# End of display.sh
##########################################################
