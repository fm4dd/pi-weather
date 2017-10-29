#!/bin/bash
##########################################################
# rrdextend.sh 20170712 Frank4DD
#
# This script extends the RRD database entry storage size
# for RRA:AVERAGE:0.5:1 from 14400 (10d) to 20160 (14d).
# The extension is a one-time change to accommodate larger
# timeframe for shortterm daily MIN/MAX table calculation.
#
# rrdtools builtin consolidation runs on GMT midnight, and
# using it causes a timezone offset resulting in a wrong
# association of MIN/MAX values. For now, we use the full
# resolution data set for it, and need to extent it to cover
# the needed 12-day timeperiod for shortterm MIN/MAX table.
#
# It only needs to run once, and is kept as reference for
# similar tasks in the future.
##########################################################
echo "rrdextend.sh: Extending RRD database for pi-weather"
RRD=/home/pi/sensor/rrd/am2302.rrd

##########################################################
# Check if the database already exists - Don't overwrite!
##########################################################
if [[ -f ./resize.rrd ]]; then
  echo "rrdextend.sh: Skipping extension, RRD database [./resize.rrd] exists." >&2
  exit -1
fi

##########################################################
# Check if the rrdtool database system is installed      #
##########################################################
if ! [ -x "$(command -v rrdtool)" ]; then
  echo "rrdextend.sh: Error - rrdtool is not installed." >&2
  exit -1
fi

##########################################################
# Calling rrdtool for extending the DB size. The RRD num,
# here rra[0] can be determined with rrdtool info rrdfile
##########################################################
let NEW=1440*14
echo "rrdextend.sh: new storage 1min for 14 days = 1440 x 14 = $NEW"
echo "rrdextend.sh: old storage 1min for 10 days = 1440 x 10 = 14400"
let DIFF=$NEW-14400
echo "rrdextend.sh: calculate extension difference: $DIFF"
echo
echo "rrdextend.sh: Extending RRD database [$RRD] into [./resize.rrd]."

rrdtool resize $RRD rra[0] GROW $DIFF

if [[ -f ./resize.rrd ]]; then
  echo "rrdextend.sh: Database [./resize.rrd] created."
  ls -l ./resize.rrd
else
  echo "rrdextend.sh: Could not extend database."
  exit -1
fi
############# end of rrdextend.sh ########################
# 20170712 RRD resizing worked # script output:
#
# rrdextend.sh: Extending RRD database for pi-weather
# rrdextend.sh: new storage 1min for 14 days = 1440 x 14 = 20160
# rrdextend.sh: old storage 1min for 10 days = 1440 x 10 = 14400
# rrdextend.sh: calculate extension difference: 5760
# 
# rrdextend.sh: Extending RRD database [/home/pi/sensor/rrd/am2302.rrd] into [./resize.rrd].
# rrdextend.sh: Database [./resize.rrd] created.
# -rw-r--r-- 1 pi pi 3038476 Jul 12 14:26 ./resize.rrd
# pi@raspi2:~/pi-weather/install $ cp resize.rrd ../../pi-ws01/rrd/weather.rrd
###########################################################
