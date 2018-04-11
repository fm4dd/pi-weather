#!/bin/bash
##########################################################
# rrdcreate3.sh 20180321 Frank4DD
#
# This script creates the RRD database that will hold the
# Raspberry Pi camera light value, read in 1-min intervals.
#
# It only needs to run once at installation time.
##########################################################
echo "rrdcreate3.sh: Creating RRD file for Raspberry Pi camera light value"

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
RRD=$RRD_DIR/camlight.rrd

##########################################################
# Check for the DB folder, create one if necessary
##########################################################
if [[ ! -e $RRD_DIR ]]; then
    echo "rrdcreate3.sh: Creating database directory $RRD_DIR."
    mkdir $RRD_DIR
fi
echo "rrdcreate3.sh: Using folder [$RRD_DIR]."

##########################################################
# Check if the database already exists - Don't overwrite!
##########################################################
if [[ -f $RRD ]]; then
  echo "rrdcreate3.sh: Skipping creation, RRD database [$RRD] exists." >&2
  exit -1
fi

##########################################################
# Check if the rrdtool database system is installed      #
##########################################################
if ! [ -x "$(command -v rrdtool)" ]; then
  echo "rrdcreate3.sh: Error - rrdtool is not installed." >&2
  exit -1
fi

##########################################################
# The camera light database will hold one data source:
# ----------------------------------------------------
# 1. camera light "ilum", extracted from JPEG image by
#    using jpglight command, returns value in range 0..1
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
echo "rrdcreate3.sh: Creating RRD database [$RRD]."

rrdtool create $RRD          \
--start now --step 60s       \
DS:ilum:GAUGE:300:0:1        \
RRA:AVERAGE:0.5:1:20160      \
RRA:AVERAGE:0.5:60:17568     \
RRA:AVERAGE:0.5:1440:7320    \
RRA:MIN:0.5:60:17568         \
RRA:MAX:0.5:60:17568         \
RRA:MIN:0.5:1440:7320        \
RRA:MAX:0.5:1440:7320

if [[ -f $RRD ]]; then
  echo "rrdcreate3.sh: Database [$RRD] created."
else
  echo "rrdcreate3.sh: Could not create database [$RRD]."
  exit -1
fi

############# end of rrdcreate3.sh #######################
