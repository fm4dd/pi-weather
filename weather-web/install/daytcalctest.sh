#!/bin/bash
##########################################################
# daytcalctest.sh 20170624 Frank4DD
#
# This script tests daytcalc sunrise / sunset calculations
#
# It runs at installation time, and later if needed.
#
# Returns 0 on sucess, 1 for errors.
##########################################################
CONFIG="/home/pi/pi-ws03/etc/pi-weather.conf"
SUCCESS=0

echo "daytcalc.sh: Testing sunrise / sunset calculations"

echo "##########################################################"
echo "# Try calculating sunrise /sunset for 4 locations, and 4 "
echo "# different times."
echo "##########################################################"
echo
declare -a TIMESET=('1471059789' '1486784589' '1499341750' '1515066550')

echo "1. Leipzig, Germany (UTC+1):"
LAT=51.330832
LON=12.445130
TZ=1

for TIME in "${TIMESET[@]}"; do
  DAYT=`../src/daytcalc -t $TIME -x $LON -y $LAT -z $TZ -f`
  if [ "$DAYT" == "" ]; then
    echo "Error getting daytime information, setting 0."
    DAYT=0
  else
    echo "daytcalctest.sh: $TIME returned $DAYT"
  fi
done

echo
echo "2. Tokyo, Japan (UTC+9):"
LAT=35.610381
LON=139.628999
TZ=9

for TIME in "${TIMESET[@]}"; do
  DAYT=`../src/daytcalc -t $TIME -x $LON -y $LAT -z $TZ -f`
  if [ "$DAYT" == "" ]; then
    echo "Error getting daytime information, setting 0."
    DAYT=0
  else
    echo "daytcalctest.sh: $TIME returned $DAYT"
  fi
done

echo
echo "3. San Francisco Golden Gate Park, U.S.A (UTC-8):"
LAT=37.768837
LON=-122.462008
TZ=-8

for TIME in "${TIMESET[@]}"; do
  DAYT=`../src/daytcalc -t $TIME -x $LON -y $LAT -z $TZ -f`
  if [ "$DAYT" == "" ]; then
    echo "Error getting daytime information, setting 0."
    DAYT=0
  else
    echo "daytcalctest.sh: $TIME returned $DAYT"
  fi
done

echo
echo "4. New York Statue of Liberty, U.S.A (UTC-5):"
LAT=40.689232
LON=-74.044559
TZ=-5

for TIME in "${TIMESET[@]}"; do
  DAYT=`../src/daytcalc -t $TIME -x $LON -y $LAT -z $TZ -f`
  if [ "$DAYT" == "" ]; then
    echo "Error getting daytime information, setting 0."
    DAYT=0
  else
    echo "daytcalctest.sh: $TIME returned $DAYT"
  fi
done
