#!/bin/bash
##########################################################
# solarupdate.sh 20180324 Frank4DD
# 
# This script runs in 1-min intervals through cron. It
# it processes the received solar data files, creates or
# updates the solar RRD database, and generates the graph
# images.
#
# This script requires the station name as single argument
# and attempts to process the received data from the path
# under <$pi-web-data>/chroot/<$1>
#
# This script is called from rrdupdate.sh, after checking
# if solardata exists identified through etc/pi-solar.conf
#
# Please set config file path to your installations value!
##########################################################
echo "solarupdate.sh: Run at `date`"
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null

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
# Check for the global config file, and source it
##########################################################
GLOBALCONFIG="$SCRIPTPATH/../etc/pi-web.conf"

if [[ ! -f $GLOBALCONFIG ]]; then
  echo "Error - cannot find config file [$GLOBALCONFIG]" >&2
  exit 1
fi
echo "Using global cfg [$GLOBALCONFIG]"
readconfig GLOBALCFG < "$GLOBALCONFIG"

PVPOWER="${GLOBALCFG[pi-web-data]}/bin/pvpower"
DAYTCALC="${GLOBALCFG[pi-web-data]}/bin/daytcalc"
RRDTOOL="/usr/bin/rrdtool"

##########################################################
# Check for the station argument, and test if it exists
##########################################################
if [ $# -eq 0 ]; then
    echo "Error - No station argument supplied"
   exit 1
fi

if [[ $1 =~ ^pi-ws[0-9]{2}$ ]]; then
   echo "Process station [$1]"
   STATION=$1
else
   echo "Error - wrong station format, expecting pi-wsXX"
   exit 1
fi

##########################################################
# Check for the station config file, and source it
##########################################################
LOCALCONFIG="${GLOBALCFG[pi-web-data]}/chroot/$STATION/etc/$STATION.conf"

if [[ ! -f $LOCALCONFIG ]]; then
  echo "Error - cannot find config file [$LOCALCONFIG]" >&2
  exit 1
fi

echo "Using local cfg [$LOCALCONFIG]"
readconfig LOCALCFG < "$LOCALCONFIG"

LOGPATH="${GLOBALCFG[pi-web-data]}/chroot/$STATION/log"
VARPATH="${GLOBALCFG[pi-web-data]}/chroot/$STATION/var"

##########################################################
# Set the station timezone for data processing
##########################################################
eval TZ=${LOCALCFG[pi-weather-tzs]}
export TZ
echo "Using timezone [$TZ]"

##########################################################
# Check for solar data file, exit if it doesn't
##########################################################
SOLARFILE="$VARPATH/solar.txt"

if [[ ! -f $SOLARFILE ]]; then
   echo "Error cannot find [$SOLARFILE]"
   exit 1
fi

echo "Using [$SOLARFILE]"

##########################################################
# Check if RRD database exists, exit if it doesn't
##########################################################
RRD="${GLOBALCFG[pi-web-data]}/chroot/$STATION/rrd/solar.rrd"

if [[ ! -e $RRD ]]; then
   echo "Error cannot find [$RRD]"
else
   echo "Using [$RRD]"
fi

##########################################################
# Get solar data timestamp
##########################################################
SOLARDATA=`cat $SOLARFILE`
echo "Solardata [$SOLARDATA]"

TIME=`echo $SOLARDATA | cut -d ":" -f 1`
if [ "$TIME" == "" ] || [ "$TIME" == "Error" ]; then
  echo "Error getting timestamp from sensor data"
  exit
else
echo "Solar timestamp [$TIME]"
fi

##########################################################
# Get last RRD database update timestamp
##########################################################
OLDTIME=`$RRDTOOL last $RRD`
if [ "$TIME" = "$OLDTIME" ]; then
  echo "Error no new solar data: last update from: `date -d @$TIME`"
  exit
else
  echo "Timestamp [$TIME] = `date -d @$TIME`"
fi

##########################################################
# Recovering from a NW outage? Write outage log
##########################################################
OUTAGELOG="$LOGPATH/solar-outage.log"
RESYNCTAG="$LOGPATH/solar-resync.tag"

let TDIFF=$TIME-$OLDTIME
if [ $TDIFF -gt 90 ]; then
  echo "Recovered from approx. $TDIFF seconds network outage."
  echo "`date`: Recovered from approx. $TDIFF seconds network outage." >> $OUTAGELOG
  touch $RESYNCTAG
fi

##########################################################
# Import solar RRD database XML file before updates
##########################################################
if [ -f $VARPATH/solardb.xml.gz ]; then
   echo "Found solar RRD XML export file, restoring DB."
   gunzip $VARPATH/solardb.xml.gz
   mv $RRD $RRD.orig
   $RRDTOOL restore $VARPATH/solardb.xml $RRD
   rm $VARPATH/solardb.xml
   rm $LOGPATH/outage.log
   rm $LOGPATH/resync.flag
   REPROCESS=1 # Force recreation of monthly/yearly pngs
fi

##########################################################
# write new data into the RRD DB
##########################################################
echo "$RRDTOOL update $RRD $SOLARDATA"
$RRDTOOL updatev $RRD "$SOLARDATA"

##########################################################
# Copy the solar data into the web folder
##########################################################
WEBPATH="${GLOBALCFG[pi-web-html]}/$STATION"
SOLARSRC="$VARPATH/getsolar.htm"
SOLARDST="$WEBPATH/getsolar.htm"

if [ -f $SOLARSRC ]; then
   echo "cp $SOLARSRC $SOLARDST"
   cp $SOLARSRC $SOLARDST
fi

##########################################################
# Check if RRD database exists, exit if it doesn't
##########################################################
if [[ ! -e $RRD ]]; then
   echo "solarupdate.sh: Error cannot find RRD database."
   exit 1
fi

##########################################################
# Create the daily graph images
##########################################################
IMGPATH="${GLOBALCFG[pi-web-html]}/$STATION/images"
VPNLPNG=$IMGPATH/daily_vpnl.png # PV Panel Voltage
VBATPNG=$IMGPATH/daily_vbat.png # BAT Voltage
PBALPNG=$IMGPATH/daily_pbal.png # Energy Balance

echo -n "Creating image $VPNLPNG... "
$RRDTOOL graph $VPNLPNG -a PNG \
  --start -16h \
  --title='Panel Voltage' \
  --step=60s  \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:opcs1=$RRD:opcs:AVERAGE \
  DEF:vpnl1=$RRD:vpnl:AVERAGE \
  CDEF:v1=opcs1,0,GT,vpnl1,UNKN,IF \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF \
  AREA:dayt2#cfcfcf \
  CDEF:tneg1=dayt1,0,GT,NEGINF,UNKN,IF \
  AREA:tneg1#cfcfcf \
  AREA:vpnl1#00447755:'Volt Off' \
  AREA:v1#00447799:'Volt Charging' \
  LINE1:vpnl1#004477FF:''  \
  GPRINT:vpnl1:MIN:'Min\: %3.2lf %sV' \
  GPRINT:vpnl1:MAX:'Max\: %3.2lf %sV' \
  GPRINT:vpnl1:LAST:'Last\: %3.2lf %sV'

echo -n "Creating image $VBATPNG... "
$RRDTOOL graph $VBATPNG -a PNG \
  --start -16h \
  --title='Battery Voltage' \
  --step=60s  \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  --alt-autoscale \
  --alt-y-grid \
  DEF:vbat1=$RRD:vbat:AVERAGE \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF \
  AREA:dayt2#cfcfcf \
  CDEF:tneg1=dayt1,0,GT,NEGINF,UNKN,IF \
  AREA:tneg1#cfcfcf \
  AREA:vbat1#99001F55:'' \
  LINE1:vbat1#99001FFF:'Volt' \
  GPRINT:vbat1:MIN:'Min\: %3.2lf V' \
  GPRINT:vbat1:MAX:'Max\: %3.2lf V' \
  GPRINT:vbat1:LAST:'Last\: %3.2lf V'

echo -n "Creating image $PBALPNG... "
$RRDTOOL graph $PBALPNG -a PNG \
  --start -16h \
  --title='Power Balance' \
  --step=60s  \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:vb1=$RRD:vbat:AVERAGE \
  DEF:ib1=$RRD:ibat:AVERAGE \
  CDEF:pbat=vb1,ib1,* \
  CDEF:psur=pbat,0,GE,pbat,0,IF \
  CDEF:pdef=pbat,0,LT,pbat,0,IF \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF \
  AREA:dayt2#cfcfcf \
  CDEF:tneg1=dayt1,0,GT,NEGINF,UNKN,IF \
  AREA:tneg1#cfcfcf \
  AREA:psur#00994455:'' \
  AREA:pdef#99001F55:'' \
  LINE1:psur#009944FF:'Watt Surplus' \
  LINE1:pdef#99001FFF:'Watt Deficit' \
  CDEF:zero=dayt1,5,EQ,UNKN,0,IF \
  LINE1:zero#cfcfcfFF:''  \
  GPRINT:pbat:MIN:'Min\: %3.2lf %sW' \
  GPRINT:pbat:MAX:'Max\: %3.2lf %sW' \
  GPRINT:pbat:LAST:'Last\: %3.2lf %sW'

##########################################################
# Create the monthly graph images
##########################################################
MVPNLPNG=$IMGPATH/monthly_vpnl.png
MVBATPNG=$IMGPATH/monthly_vbat.png
MPBALPNG=$IMGPATH/monthly_pbal.png
midnight=$(date -d "00:00" +%s)

##########################################################
# Check if monthly panel file has already
# been updated today, otherwise generate.
##########################################################
if [ -f $MVPNLPNG ]; then FILEAGE=$(date -r $MVPNLPNG +%s); fi
if [ ! -f $MVPNLPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $MVPNLPNG... "

  # --------------------------------------- #
  # --x-grid defines the x-axis spacing.    #
  # format: GTM:GST:MTM:MST:LTM:LST:LPR:LFM #
  # GTM:GST base grid (Unit:How Many)       #
  # MTM:MST major grid (Unit:How Many)      #
  # LTM:LST how often labels are placed     #
  # --------------------------------------- #
  $RRDTOOL graph $MVPNLPNG -a PNG \
  --start end-21d --end 00:00 \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --title='Panel Voltage, 3 Weeks' \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:opcs1=$RRD:opcs:AVERAGE \
  DEF:vpnl1=$RRD:vpnl:AVERAGE \
  AREA:vpnl1#00447755:'Volt Off' \
  CDEF:v1=opcs1,0,GT,vpnl1,UNKN,IF \
  AREA:v1#00447799:'Volt Charging' \
  LINE1:vpnl1#004477FF:''  \
  GPRINT:vpnl1:MIN:'Min\: %3.2lf %sV' \
  GPRINT:vpnl1:MAX:'Max\: %3.2lf %sV' \
  GPRINT:vpnl1:LAST:'Last\: %3.2lf %sV'
fi

##########################################################
# Check if monthly battery file has already
# been updated today, otherwise generate.
##########################################################
if [ -f $MVBATPNG ]; then FILEAGE=$(date -r $MVBATPNG +%s); fi
if [ ! -f $MVBATPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $MVBATPNG... "

  $RRDTOOL graph $MVBATPNG -a PNG \
  --start end-21d --end 00:00 \
  --title='Battery Voltage, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --alt-autoscale \
  --lower-limit=12.0 \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:vbat1=$RRD:vbat:AVERAGE \
  AREA:vbat1#99001F55:'' \
  LINE1:vbat1#99001FFF:'Volt' \
  GPRINT:vbat1:MIN:'Min\: %3.2lf V' \
  GPRINT:vbat1:MAX:'Max\: %3.2lf V' \
  GPRINT:vbat1:LAST:'Last\: %3.2lf V'
fi

##########################################################
# Check if monthly power file has already
# been updated today, otherwise generate.
##########################################################
if [ -f $MPBALPNG ]; then FILEAGE=$(date -r $MPBALPNG +%s); fi
if [ ! -f $MPBALPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $MPBALPNG... "

  $RRDTOOL graph $MPBALPNG -a PNG \
  --start end-21d --end 00:00 \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --title='Power Balance, 3 Weeks' \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:vb1=$RRD:vbat:AVERAGE \
  DEF:ib1=$RRD:ibat:AVERAGE \
  CDEF:pbat=vb1,ib1,* \
  CDEF:psur=pbat,0,GE,pbat,UNKN,IF \
  CDEF:pdef=pbat,0,LT,pbat,UNKN,IF \
  AREA:psur#00994455:'' \
  LINE1:psur#009944FF:'Watt Surplus' \
  AREA:pdef#99001F55:'' \
  LINE1:pdef#99001FFF:'Watt Deficit' \
  GPRINT:pbat:MIN:'Min\: %3.2lf %sW' \
  GPRINT:pbat:MAX:'Max\: %3.2lf %sW' \
  GPRINT:pbat:LAST:'Last\: %3.2lf %sW'
fi

##########################################################
# Create the yearly graph images
##########################################################
YVPNLPNG=$IMGPATH/yearly_vpnl.png
YVBATPNG=$IMGPATH/yearly_vbat.png
YPBALPNG=$IMGPATH/yearly_pbal.png

##########################################################
# Check if yearly VPNL file has already
# been updated today, otherwise generate
##########################################################
if [ -f $YVPNLPNG ]; then FILEAGE=$(date -r $YVPNLPNG +%s); fi
if [ ! -f $YVPNLPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $YVPNLPNG... "

  $RRDTOOL graph $YVPNLPNG -a PNG \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Panel Voltage, Yearly View' \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:vpnl1=$RRD:vpnl:AVERAGE \
  AREA:vpnl1#00447799:'' \
  LINE1:vpnl1#004477FF:'Volt'  \
  GPRINT:vpnl1:MIN:'Min\: %3.2lf %sV' \
  GPRINT:vpnl1:MAX:'Max\: %3.2lf %sV' \
  GPRINT:vpnl1:LAST:'Last\: %3.2lf %sV'
fi

##########################################################
# Check if yearly VBAT file has already
# been updated today, otherwise generate
##########################################################
if [ -f $YVBATPNG ]; then FILEAGE=$(date -r $YVBATPNG +%s); fi
if [ ! -f $YVBATPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $YVBATPNG... "

  $RRDTOOL graph $YVBATPNG -a PNG \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Battery Voltage, Yearly View' \
  --alt-autoscale \
  --lower-limit=11.0 \
  --left-axis-format "%2.1lf" \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:vbat1=$RRD:vbat:AVERAGE \
  AREA:vbat1#99001F55:'' \
  LINE1:vbat1#99001FFF:'Volt' \
  GPRINT:vbat1:MIN:'Min\: %3.2lf V' \
  GPRINT:vbat1:MAX:'Max\: %3.2lf V' \
  GPRINT:vbat1:LAST:'Last\: %3.2lf V'
fi

##########################################################
# Check if yearly power file has already
# been updated today, otherwise generate
##########################################################
if [ -f $YPBALPNG ]; then FILEAGE=$(date -r $YPBALPNG +%s); fi
if [ ! -f $YPBALPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $YLOADPNG... "

  $RRDTOOL graph $YPBALPNG -a PNG \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Power Balance, Yearly View' \
  --width=619 \
  --height=77 \
  --border=1  \
  --slope-mode \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:vb1=$RRD:vbat:AVERAGE \
  DEF:ib1=$RRD:ibat:AVERAGE \
  CDEF:pbat=vb1,ib1,* \
  CDEF:psur=pbat,0,GE,pbat,UNKN,IF \
  CDEF:pdef=pbat,0,LT,pbat,UNKN,IF \
  AREA:psur#00994455:'' \
  LINE1:psur#009944FF:'Watt Surplus' \
  AREA:pdef#99001F55:'' \
  LINE1:pdef#99001FFF:'Watt Deficit' \
  GPRINT:pbat:MIN:'Min\: %3.2lf %sW' \
  GPRINT:pbat:MAX:'Max\: %3.2lf %sW' \
  GPRINT:pbat:LAST:'Last\: %3.2lf %sW'
fi

##########################################################
# Daily update of the 12-days power generation htm file
##########################################################
DAYHTMFILE="${GLOBALCFG[pi-web-html]}/$STATION/daypower.htm"

if [ -f $DAYHTMFILE ]; then FILEAGE=$(date -r $DAYHTMFILE +%s); fi
if [ ! -f $DAYHTMFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating $DAYHTMFILE... "
  $PVPOWER -s $RRD -d $DAYHTMFILE
  echo " Done."
fi

unset TZ
echo "solarupdate.sh: End of script at `date`"
##########################################################
# End of solarupdate.sh
##########################################################
