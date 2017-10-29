#!/bin/bash
##########################################################
# rrdrepair.sh 20170723 Frank4DD
#
# This script can replace RRD DB entries with wrong sensor
# data, using a prepared VIM input file. Because the RRD
# file gets updated every 60 seconds, we need to start
# quickly after the update, and finish before the next.
#
# Approx. 8-9 changes can be done before the time is up.
# Keep an eye on start/end time during the rehearsal run.
#
# Warning: Working with this script needs great care not
#          to destroy the original data by accident. :-)
#
# ./rrdrepair    --> test run without overwriting
# ./rrdrepair -p --> real run with live data update
##########################################################
echo "rrdrepair.sh start: `date`"

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
echo "# 1. Check for prd argument, and load the config file"
echo "##########################################################"
CONFIG="../etc/pi-weather.conf"

if [[ ! -f $CONFIG ]]; then
  echo "rrdrepair.sh: Error - cannot find config file [$CONFIG]" >&2
  exit 1
fi

readconfig MYCONFIG < "$CONFIG"
STRLEN=${#MYCONFIG[@]}
echo "rrdrepair.sh: Reading file [$CONFIG] with [$STRLEN] values"
WHOME=${MYCONFIG[pi-weather-dir]}

if [ $1 ] && [ $1 == "-p" ]; then
   echo "rrdrepair.sh: final PRD run, updating real data"
else
   echo "rrdrepair.sh: test run, simulating execution"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 2. Catch the time after the existing RRD DB was updated"
echo "##########################################################"
OLDRRD="$WHOME/rrd/weather.rrd"

if [[ ! -f $OLDRRD ]]; then
   echo "Error - cannot find RRD file [$OLDRRD]" >&2
   exit 1
fi

while ( true ); do
   let RRDAGE=`echo $(($(date +%s) - $(date +%s -r $OLDRRD)))`
   echo "date: `date` file update: `date -r $OLDRRD` rrdage: $RRDAGE"
   if [ $RRDAGE -eq 0 ] || [ $RRDAGE -eq 1 ]; then
      echo "RRD Updated! date: `date` file update: `date -r $OLDRRD`"
      sleep 1
      break
   fi
   sleep 1
done

echo "Done."
echo

echo "##########################################################"
echo "# 3. Take existing RRD DB and convert to local XML extract"
echo "##########################################################"
TMPXML="$WHOME/var/tmp/rrdrepair.xml"

echo "rrdtool dump $OLDRRD $TMPXML"
rrdtool dump $OLDRRD $TMPXML
echo "Done."
echo

echo "##########################################################"
echo "# 4. Edit the prepared lines in XML extract, and save the"
echo "# result. Lines were identified in a earlier XML extract."
echo "##########################################################"
FIXVIM=./rrdrepair.vi

if [[ ! -f $FIXVIM ]]; then
   echo "Error - cannot find VIM file [$FIXVIM]" >&2
   exit 1
fi

# -n disables vi's swap file for speed-up, but no backup exists
echo "vi -n -s $FIXVIM $TMPXML"
vi -n -s $FIXVIM $TMPXML
echo "Done."
echo

echo "##########################################################"
echo "# 5. Import $TMPXML data to RRD"
echo "##########################################################"
TMPRRD="$WHOME/var/tmp/rrdrepair.rrd"

if [[ ! -f $TMPXML ]]; then
   echo "Error - cannot find XML file [$TMPXML]" >&2
   exit 1
fi

echo "rrdtool restore $TMPXML $TMPRRD"
rrdtool restore $TMPXML $TMPRRD
echo "Done."
echo

echo "##########################################################"
echo "# 6. Backup original RRD DB $OLDRRD"
echo "##########################################################"
echo "cp $OLDRRD $OLDRRD.orig"
cp $OLDRRD $OLDRRD.orig

echo "Done."
echo

echo "##########################################################"
echo "# 7. Replace with updated RRD DB $TMPRRD"
echo "##########################################################"

let RRDAGE=`echo $(($(date +%s) - $(date +%s -r $OLDRRD)))`
echo "date: `date` file update: `date -r $OLDRRD` rrdage: $RRDAGE"
echo "cp $TMPRRD $OLDRRD"

if [ $1 ] && [ $1 == "-p" ]; then
   cp $TMPRRD $OLDRRD
else
   echo "No execution, testing only"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 8. Cleanup temp files $TMPXML $TMPRRD"
echo "##########################################################"

echo "rm $TMPXML $TMPRRD"
echo "mv $FIXVIM $FIXVIM.`date +%Y%m%d`"

if [ $1 ] && [ $1 == "-p" ]; then
   rm $TMPXML $TMPRRD
   mv $FIXVIM $FIXVIM.`date +%Y%m%d`
else
   echo "No execution, testing only"
fi

echo "Done."
echo

echo "##########################################################"
echo "rrdrepair.sh end: `date`"
