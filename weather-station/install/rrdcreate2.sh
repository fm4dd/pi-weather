#!/bin/bash
##########################################################
# rrdcreate2.sh 20170624 Frank4DD
#
# This script creates the RRD database that will hold the
# Raspberry Pi CPU temperature, read in 1-min intervals.
#
# It only needs to run once at installation time.
##########################################################
echo "rrdcreate2.sh: Creating RRD file for Raspberry Pi CPU temperature"

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
CONFIG=../etc/pi-weather.conf
if [[ ! -f $CONFIG ]]; then
  echo "rrdcreate2.sh: Error - cannot find config file [$CONFIG]" >&2
  exit -1
fi
readconfig MYCONFIG < "$CONFIG"

##########################################################
# Get RRD directory and set RRD for Raspi CPU temperature
##########################################################
RRD_DIR=${MYCONFIG[pi-weather-dir]}/rrd
RRD=$RRD_DIR/rpitemp.rrd

##########################################################
# Check for the DB folder, create one if necessary
##########################################################
if [[ ! -e $RRD_DIR ]]; then
    echo "rrdcreate2.sh: Creating database directory $RRD_DIR."
    mkdir $RRD_DIR
fi
echo "rrdcreate2.sh: Using folder [$RRD_DIR]."

##########################################################
# Check if the database already exists - Don't overwrite!
##########################################################
if [[ -f $RRD ]]; then
  echo "rrdcreate2.sh: Skipping creation, RRD database [$RRD] exists." >&2
  exit -1
fi

##########################################################
# Check if the rrdtool database system is installed      #
##########################################################
if ! [ -x "$(command -v rrdtool)" ]; then
  echo "rrdcreate2.sh: Error - rrdtool is not installed." >&2
  exit -1
fi

##########################################################
# The CPU Temp RRD database will hold four data sources:
# ----------------------------------------------
# 1. CPU temperature (in degree Celsius)
#
# The data slots are allocated as follows:
# ----------------------------------------
# 1. store 1-min readings in 10080 entries (7 days: 60s*24hr*14d)
# RRA:AVERAGE:0.5:1:10080
# 2. store one 10-min average in 4464 entries (1 month: 1*6*24*31d)
# RRA:AVERAGE:0.5:10:4464
# 3. store one 120-min average in 4380 entries (1 year: 12x2hrx365d)
# RRA:AVERAGE:0.5:120:4380
#
# additionally, we store MIN and MAX values at the same intervals.
##########################################################
echo "rrdcreate2.sh: Creating RRD database [$RRD]."

rrdtool create $RRD          \
--start now --step 60s       \
DS:temp:GAUGE:300:0:150      \
RRA:AVERAGE:0.5:1:10080      \
RRA:AVERAGE:0.5:10:4464      \
RRA:AVERAGE:0.5:120:4380     \
RRA:MIN:0.5:10:4464          \
RRA:MAX:0.5:10:4464          \
RRA:MIN:0.5:120:4380         \
RRA:MAX:0.5:120:4380

if [[ -f $RRD ]]; then
  echo "rrdcreate2.sh: Database [$RRD] created."
else
  echo "rrdcreate2.sh: Could not create database [$RRD]."
  exit -1
fi

############# end of rrdcreate2.sh #######################
