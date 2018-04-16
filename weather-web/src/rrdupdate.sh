#!/bin/bash
##########################################################
# rrdupdate.sh 20170624 Frank4DD
# 
# This script runs in 1-min intervals through cron. It
# it processes the independently generated sensor data file,
# updates the RRD database, and generates the graph images.
#
# It also handles the files that are created once per day:
# 1) pick up the timelapse movie received after midnight
# 2) pickup and import the daily RRD XML export file that
# was send from the weather station (this helps filling any
# data gaps created by network outages).
#
# This script requires the station name as single argument
# and attempts to process the received data from the path
# under <$pi-web-data>/chroot/<$1>
#
# Please set config file path to your installations value!
##########################################################
echo "rrdupdate.sh: Run at `date`"
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

DAYTCALC="${GLOBALCFG[pi-web-data]}/bin/daytcalc"
OUTLIER="${GLOBALCFG[pi-web-data]}/bin/outlier"
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
# Check for sensor data file, exit if it doesn't
##########################################################
SENSORFILE="$VARPATH/sensor.txt"

if [[ ! -f $SENSORFILE ]]; then
   echo "Error cannot find [$SENSORFILE]"
   exit 1
fi

echo "Using [$SENSORFILE]"

##########################################################
# Check if RRD database exists, exit if it doesn't
##########################################################
RRD="${GLOBALCFG[pi-web-data]}/chroot/$STATION/rrd/$STATION.rrd"

if [[ ! -e $RRD ]]; then
   echo "Error cannot find [$RRD]"
   exit 1
fi

echo "Using [$RRD]"

##########################################################
# Get Sensor data timestamp
##########################################################
SENSORDATA=`cat $SENSORFILE`
echo "Sensordata [$SENSORDATA]"

TIME=`echo $SENSORDATA | cut -d " " -f 1`
if [ "$TIME" == "" ] || [ "$TIME" == "Error" ]; then
  echo "Error getting timestamp from sensor data"
  exit
fi

##########################################################
# Get last RRD database update timestamp
##########################################################
OLDTIME=`$RRDTOOL last $RRD`
if [ "$TIME" = "$OLDTIME" ]; then
  echo "Error no new sensor data: last update from: `date -d @$TIME`"
  exit
else
  echo "Timestamp [$TIME] = `date -d @$TIME`"
fi

##########################################################
# Recovering from a NW outage? Write outage log
##########################################################
OUTAGELOG="$LOGPATH/outage.log"
RESYNCTAG="$LOGPATH/resync.tag"

let TDIFF=$TIME-$OLDTIME
if [ $TDIFF -gt 90 ]; then
  echo "Recovered from approx. $TDIFF seconds network outage."
  echo "`date`: Recovered from approx. $TDIFF seconds network outage." >> $OUTAGELOG
  touch $RESYNCTAG
fi

##########################################################
# Data Source 1: Temperature
##########################################################
TEMP=`echo $SENSORDATA | cut -d " " -f 2 | cut -c 6- | cut -d "*" -f 1`
if [ "$TEMP" == "" ]; then
  echo "Error getting temperature from sensor.txt"
  exit
fi

##########################################################
# Temperature outlier detection
##########################################################
LIMIT=5
$OUTLIER -s $RRD -d temp -n $TEMP -p $LIMIT
if [ $? == 1 ]; then
  echo "`date -R` [$SENSORDATA] -> temperature outlier [$TEMP]." >> $LOGPATH/outlier.log
  echo "Error temperature [$TEMP] is a outlier."
else
  echo "Temperature [$TEMP] outlier detection OK."
fi

##########################################################
# Data Source 2: Humidity
##########################################################
HUMI=`echo $SENSORDATA | cut -d " " -f 3 | cut -c 10- | cut -d "%" -f 1`
if [ "$HUMI" == "" ]; then
  echo "Error getting humidity from sensor.txt"
  exit
fi

##########################################################
# Humidity outlier detection
##########################################################
LIMIT=15
$OUTLIER -s $RRD -d humi -n $HUMI -p $LIMIT
if [ $? == 1 ]; then
  echo "`date -R` [$SENSORDATA] -> humidity outlier [$HUMI]." >> $LOGPATH/outlier.log
  echo "Error humidity [$HUMI] is a outlier."
else
  echo "Humidity [$HUMI] outlier detection OK."
fi

##########################################################
# Data Source 3: Pressure
##########################################################
BMPR=`echo $SENSORDATA | cut -d " " -f 4 | cut -c 10- | cut -d "P" -f 1`
if [ "$BMPR" == "" ]; then
  echo "Error getting pressure from sensor.txt"
  exit
fi

##########################################################
# Pressure outlier detection
##########################################################
LIMIT=12000
$OUTLIER -s $RRD -d bmpr -n $BMPR -p $LIMIT
if [ $? == 1 ]; then
  echo "`date -R` [$SENSORDATA] -> pressure outlier [$BMPR]." >> $LOGPATH/outlier.log
  echo "Error pressure [$BMPR] is a outlier."
else
  echo "Pressure [$BMPR] outlier detection OK."
fi

##########################################################
# Data Source 4: Daytime
# ./daytcalc -t 1486784589 -x 12.45277778 -y 51.340277778 -z 1
##########################################################
LON="${LOCALCFG[pi-weather-lon]}"
LAT="${LOCALCFG[pi-weather-lat]}"
DAYTIME=('day' 'night');

echo "$DAYTCALC -t $TIME -x $LON -y $LAT -s $TZ"
`$DAYTCALC -t $TIME -x $LON -y $LAT -s $TZ`

DAYT=$?
if [ "$DAYT" == "" ]; then
  echo "Error getting daytime information, setting 0."
  DAYT=0
else
  echo "daytcalc $TIME returned [$DAYT] [${DAYTIME[$DAYT]}]."
fi

##########################################################
# Import any sensor-send database XML file before updates
##########################################################
if [ -f $VARPATH/rrdcopy.xml.gz ]; then
   echo "Found sensor RRD XML export file, restoring DB."
   gunzip $VARPATH/rrdcopy.xml.gz
   mv $RRD $RRD.orig
   $RRDTOOL restore $VARPATH/rrdcopy.xml $RRD
   rm $VARPATH/rrdcopy.xml
   rm $LOGPATH/outage.log
   rm $LOGPATH/resync.flag
   REPROCESS=1 # Force recreation of monthly/yearly pngs
fi

##########################################################
# write new data into the RRD DB
##########################################################
echo "$RRDTOOL update $RRD $TIME:$TEMP:$HUMI:$BMPR:$DAYT"
$RRDTOOL updatev $RRD "$TIME:$TEMP:$HUMI:$BMPR:$DAYT"

##########################################################
# Write the sensor data into web format to web folder
##########################################################
WEBPATH="${GLOBALCFG[pi-web-html]}/$STATION"

# BMPR is in Pascal, convert to hPA
calc(){ awk "BEGIN { print "$*" }"; }
HPA=`calc $BMPR/100`

cat <<EOM >$WEBPATH/getsensor.htm
<table><tr>
<td class="sensordata">Air Temperature:<span class="sensorvalue">$TEMP&deg;C</span></td>
<td class="sensorspace"></td>
<td class="sensordata">Relative Humidity:<span class="sensorvalue">$HUMI&thinsp;%</span></td>
<td class="sensorspace"></td>
<td class="sensordata">Barometric Pressure:<span class="sensorvalue">$HPA&thinsp;hPa</span></td>
</tr></table>
EOM

##########################################################
# Copy the station health data into the web folder
##########################################################
RDATSRC="$VARPATH/raspidat.htm"
RDATDST="$WEBPATH/raspidat.htm"

if [ -f $RDATSRC ]; then
   echo "cp $RDATSRC $RDATDST"
   cp $RDATSRC $RDATDST
else
   echo "Error cannot find $RDATSRC"
fi

##########################################################
# Copy the camera image into the web folder
##########################################################
IMGPATH="${GLOBALCFG[pi-web-html]}/$STATION/images"
WCAMSRC="$VARPATH/raspicam.jpg"
WCAMDST="$IMGPATH/raspicam.jpg"

if [ -f $WCAMSRC ]; then
   echo "cp $WCAMSRC $WCAMDST"
   cp $WCAMSRC $WCAMDST
else
   echo "Error cannot find $WCAMSRC"
fi

##########################################################
# If we have solar data, start the update processing
##########################################################
SOLARCONF=${GLOBALCFG[pi-web-data]}/chroot/$STATION/etc/pi-solar.conf
SOLARLOG=${GLOBALCFG[pi-web-data]}/chroot/$STATION/log/pi-solar.log
echo "Checking for solar integration: $SOLARCONF"
if [ -f  $SOLARCONF ]; then
   echo "Calling: ( $SCRIPTPATH/solarupdate.sh $1 > $SOLARLOG 2>&1 ) &"
   ( $SCRIPTPATH/solarupdate.sh $1 > $SOLARLOG 2>&1 ) &
fi


##########################################################
# Create the daily graph images
##########################################################
TEMPPNG="$IMGPATH/daily_temp.png"
HUMIPNG="$IMGPATH/daily_humi.png"
BMPRPNG="$IMGPATH/daily_bmpr.png"

echo -n "Creating image $TEMPPNG... "

$RRDTOOL graph $TEMPPNG -a PNG \
  --start -16h \
  --title='Temperature' \
  --step=60s  \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:temp1=$RRD:temp:AVERAGE \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \
  'CDEF:tneg1=dayt1,0,GT,NEGINF,UNKN,IF' \
  'AREA:tneg1#cfcfcf' \
  'AREA:temp1#99001F:Temperature in °C' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'

echo -n "Creating image $HUMIPNG... "

$RRDTOOL graph $HUMIPNG -a PNG \
  --start -16h \
  --title='Relative Humidity' \
  --step=60s  \
  --upper-limit=100 \
  --lower-limit=0 \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:humi1=$RRD:humi:AVERAGE \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \
  'AREA:humi1#004477:Humidity in percent' \
  'GPRINT:humi1:MIN:Min\: %3.2lf' \
  'GPRINT:humi1:MAX:Max\: %3.2lf' \
  'GPRINT:humi1:LAST:Last\: %3.2lf'

echo -n "Creating image $BMPRPNG... "

$RRDTOOL graph $BMPRPNG -a PNG \
  --start -16h \
  --title='Barometric Pressure' \
  --step=60s  \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  --alt-autoscale \
  --alt-y-grid \
  --units-exponent=0 \
  DEF:bmpr1=$RRD:bmpr:AVERAGE \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:bmpr2=bmpr1,100,/' \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \
  'AREA:bmpr2#007744:Barometric Pressure in hPa' \
  'GPRINT:bmpr2:MIN:Min\: %3.2lf' \
  'GPRINT:bmpr2:MAX:Max\: %3.2lf' \
  'GPRINT:bmpr2:LAST:Last\: %3.2lf'

##########################################################
# Create the monthly graph images
##########################################################
MTEMPPNG=$IMGPATH/monthly_temp.png
MHUMIPNG=$IMGPATH/monthly_humi.png
MBMPRPNG=$IMGPATH/monthly_bmpr.png

##########################################################
# Check if monthly temp file has already
# been updated today, otherwise generate.
##########################################################
midnight=$(date -d "00:00" +%s)
if [ -f $MTEMPPNG ]; then FILEAGE=$(date -r $MTEMPPNG +%s); fi
if [ ! -f $MTEMPPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $MTEMPPNG... "

  # --------------------------------------- #
  # --x-grid defines the x-axis spacing.    #
  # format: GTM:GST:MTM:MST:LTM:LST:LPR:LFM #
  # GTM:GST base grid (Unit:How Many)       #
  # MTM:MST major grid (Unit:How Many)      #
  # LTM:LST how often labels are placed     #
  # --------------------------------------- #
  $RRDTOOL graph $MTEMPPNG -a PNG \
  --start end-21d --end 00:00 \
  --title='Temperature, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:temp1=$RRD:temp:AVERAGE \
  'AREA:temp1#99001F:Temperature in °C' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if monthly humi file has already
# been updated today, otherwise generate.
##########################################################
if [ -f $MHUMIPNG ]; then FILEAGE=$(date -r $MHUMIPNG +%s); fi
if [ ! -f $MHUMIPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $MHUMIPNG... "

  $RRDTOOL graph $MHUMIPNG -a PNG \
  --start end-21d --end 00:00 \
  --title='Relative Humidity, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --upper-limit=100 \
  --lower-limit=0 \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:humi1=$RRD:humi:AVERAGE \
  'AREA:humi1#004477:Humidity in percent' \
  'GPRINT:humi1:MIN:Min\: %3.2lf' \
  'GPRINT:humi1:MAX:Max\: %3.2lf' \
  'GPRINT:humi1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if monthly bmpr file has already
# been updated today, otherwise generate.
##########################################################
if [ -f $MBMPRPNG ]; then FILEAGE=$(date -r $MBMPRPNG +%s); fi
if [ ! -f $MBMPRPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $MBMPRPNG... "

  $RRDTOOL graph $MBMPRPNG -a PNG \
  --start end-21d --end 00:00 \
  --title='Barometric Pressure, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --width=619 \
  --height=77 \
  --border=1  \
  --alt-autoscale \
  --alt-y-grid \
  --units-exponent=0 \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:bmpr1=$RRD:bmpr:AVERAGE \
  'CDEF:bmpr2=bmpr1,100,/' \
  'AREA:bmpr2#007744:Barometric Pressure in hPa' \
  'GPRINT:bmpr2:MIN:Min\: %3.2lf' \
  'GPRINT:bmpr2:MAX:Max\: %3.2lf' \
  'GPRINT:bmpr2:LAST:Last\: %3.2lf'
fi

##########################################################
# Create the yearly graph images
##########################################################
YTEMPPNG=$IMGPATH/yearly_temp.png
YHUMIPNG=$IMGPATH/yearly_humi.png
YBMPRPNG=$IMGPATH/yearly_bmpr.png

##########################################################
# Check if yearly temp file has already 
# been updated today, otherwise generate
##########################################################
if [ -f $YTEMPPNG ]; then FILEAGE=$(date -r $YTEMPPNG +%s); fi
if [ ! -f $YTEMPPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $YTEMPPNG... "

  $RRDTOOL graph $YTEMPPNG -a PNG \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Temperature, Yearly View' \
  --slope-mode \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:temp1=$RRD:temp:AVERAGE \
  'AREA:temp1#99001F:Temperature in °C' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if yearly humi file has already
# been updated today, otherwise generate
##########################################################
if [ -f $YHUMIPNG ]; then FILEAGE=$(date -r $YHUMIPNG +%s); fi
if [ ! -f $YHUMIPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $YHUMIPNG... "

  $RRDTOOL graph $YHUMIPNG -a PNG \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Relative Humidity, Yearly View' \
  --upper-limit=100 \
  --lower-limit=0 \
  --slope-mode \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:humi1=$RRD:humi:AVERAGE \
  'AREA:humi1#004477:Humidity in percent' \
  'GPRINT:humi1:MIN:Min\: %3.2lf' \
  'GPRINT:humi1:MAX:Max\: %3.2lf' \
  'GPRINT:humi1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if yearly bmpr file has already
# been updated today, otherwise generate
##########################################################
if [ -f $YBMPRPNG ]; then FILEAGE=$(date -r $YBMPRPNG +%s); fi
if [ ! -f $YBMPRPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $YBMPRPNG... "

  $RRDTOOL graph $YBMPRPNG -a PNG \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Barometric Pressure, Yearly View' \
  --slope-mode \
  --width=619 \
  --height=77 \
  --border=1  \
  --alt-autoscale \
  --alt-y-grid \
  --units-exponent=0 \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:bmpr1=$RRD:bmpr:AVERAGE \
  'CDEF:bmpr2=bmpr1,100,/' \
  'AREA:bmpr2#007744:Barometric Pressure in hPa' \
  'GPRINT:bmpr2:MIN:Min\: %3.2lf' \
  'GPRINT:bmpr2:MAX:Max\: %3.2lf' \
  'GPRINT:bmpr2:LAST:Last\: %3.2lf'
fi

##########################################################
# Create the 18-year graph images
##########################################################
TWYTEMPPNG=$IMGPATH/twyear_temp.png
TWYHUMIPNG=$IMGPATH/twyear_humi.png
TWYBMPRPNG=$IMGPATH/twyear_bmpr.png

##########################################################
# Check if the 18-year temp file has already
# been updated today, otherwise generate it.
##########################################################
if [ -f $TWYTEMPPNG ]; then FILEAGE=$(date -r $TWYTEMPPNG +%s); fi
if [ ! -f $TWYTEMPPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $TWYTEMPPNG... "

  $RRDTOOL graph $TWYTEMPPNG -a PNG \
  --start end-18years --end 00:00 \
  --x-grid YEAR:1:YEAR:10:YEAR:1:31536000:%Y \
  --title='Temperature, 18-Year View' \
  --slope-mode \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:temp1=$RRD:temp:AVERAGE \
  'AREA:temp1#99001F:Temperature in °C' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if the 18-year humi file has already
# been updated today, otherwise generate it.
##########################################################
if [ -f $TWYHUMIPNG ]; then FILEAGE=$(date -r $TWYHUMIPNG +%s); fi
if [ ! -f $TWYHUMIPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $TWYHUMIPNG... "

  $RRDTOOL graph $TWYHUMIPNG -a PNG \
  --start end-18years --end 00:00 \
  --x-grid YEAR:1:YEAR:10:YEAR:1:31536000:%Y \
  --title='Humidity, 18-Year View' \
  --upper-limit=100 \
  --lower-limit=0 \
  --slope-mode \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:humi1=$RRD:humi:AVERAGE \
  'AREA:humi1#004477:Humidity in percent' \
  'GPRINT:humi1:MIN:Min\: %3.2lf' \
  'GPRINT:humi1:MAX:Max\: %3.2lf' \
  'GPRINT:humi1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if the 18-year bmpr file has already
# been updated today, otherwise generate it.
##########################################################
if [ -f $TWYBMPRPNG ]; then FILEAGE=$(date -r $TWYBMPRPNG +%s); fi
if [ ! -f $TWYBMPRPNG ] || [[ "$FILEAGE" < "$midnight" ]] || [ -v REPROCESS ]; then
  echo -n "Creating image $TWYBMPRPNG... "

  $RRDTOOL graph $TWYBMPRPNG -a PNG \
  --start end-18years --end 00:00 \
  --x-grid YEAR:1:YEAR:10:YEAR:1:31536000:%Y \
  --title='Barometric Pressure, 18-Year View' \
  --slope-mode \
  --width=619 \
  --height=77 \
  --border=1  \
  --alt-autoscale \
  --alt-y-grid \
  --units-exponent=0 \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:bmpr1=$RRD:bmpr:AVERAGE \
  'CDEF:bmpr2=bmpr1,100,/' \
  'AREA:bmpr2#007744:Barometric Pressure in hPa' \
  'GPRINT:bmpr2:MIN:Min\: %3.2lf' \
  'GPRINT:bmpr2:MAX:Max\: %3.2lf' \
  'GPRINT:bmpr2:LAST:Last\: %3.2lf'
fi

##########################################################
# Daily update of the yearly Min/Max Temperature htm file
##########################################################
YEARSRCFILE=$VARPATH/yearmimax.htm
YEARHTMFILE=$WEBPATH/yearmimax.htm
YEARHTMAGE=0
YEARSRCAGE=0

if [ ! -f $YEARHTMFILE ] && [ -f $YEARSRCFILE ]; then
  echo -n "Creating  $YEARHTMFILE... "
  cp $YEARSRCFILE $YEARHTMFILE
  echo " Done."
fi

if [ -f $YEARHTMFILE ]; then YEARHTMAGE=$(date -r $YEARHTMFILE +%s); fi
if [ -f $YEARSRCFILE ]; then YEARSRCAGE=$(date -r $YEARSRCFILE +%s); fi

if [ -f $YEARHTMFILE ] && [ -f $YEARSRCFILE ] && [ $YEARSRCAGE -gt $YEARHTMAGE ]; then
  echo -n "Updating  $YEARHTMFILE... "
  cp $YEARSRCFILE $YEARHTMFILE
  echo " Done."
fi

##########################################################
# Daily update of the monthly Min/Max Temperature htm file
##########################################################
MONSRCFILE=$VARPATH/momimax.htm
MONHTMFILE=$WEBPATH/momimax.htm
MONHTMAGE=0
MONSRCAGE=0

if [ ! -f $MONHTMFILE ] && [ -f $MONSRCFILE ]; then
  echo -n "Creating  $MONHTMFILE... "
  cp $MONSRCFILE $MONHTMFILE
  echo " Done."
fi

if [ -f $MONHTMFILE ]; then MONHTMAGE=$(date -r $MONHTMFILE +%s); fi
if [ -f $MONSRCFILE ]; then MONSRCAGE=$(date -r $MONSRCFILE +%s); fi

if [ -f $MONHTMFILE ] && [ -f $MONSRCFILE ] && [ $MONSRCAGE -gt $MONHTMAGE ]; then
  echo -n "Updating  $MONHTMFILE... "
  cp $MONSRCFILE $MONHTMFILE
  echo " Done."
fi

##########################################################
# Daily update of the 12-days Min/Max Temperature htm file
##########################################################
DAYSRCFILE=$VARPATH/daymimax.htm
DAYHTMFILE=$WEBPATH/daymimax.htm
DAYSRCAGE=0
DAYHTMAGE=0

if [ ! -f $DAYHTMFILE ] && [ -f $DAYSRCFILE ]; then
  echo -n "Creating  $DAYHTMFILE... "
  cp $DAYSRCFILE $DAYHTMFILE
  echo " Done."
fi

if [ -f $DAYHTMFILE ]; then DAYHTMAGE=$(date -r $DAYHTMFILE +%s); fi
if [ -f $DAYSRCFILE ]; then DAYSRCAGE=$(date -r $DAYSRCFILE +%s); fi

if [ -f $DAYHTMFILE ] && [ -f $DAYSRCFILE ] && [ $DAYSRCAGE -gt $DAYHTMAGE ]; then
  echo -n "Updating  $DAYHTMFILE... "
  cp $DAYSRCFILE $DAYHTMFILE
  echo " Done."
fi

##########################################################
# Daily update of the sunrise/sunset data file
##########################################################
DAYTIMEFILE=$WEBPATH/daytime.htm

if [ -f $DAYTIMEFILE ]; then FILEAGE=$(date -r $DAYTIMEFILE +%s); fi
if [ ! -f $DAYTIMEFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  NOW=`date +%s`
  echo "Creating  $DAYTIMEFILE"
  echo "$DAYTCALC -t $NOW -x $LON -y $LAT -s $TZ -f > $DAYTIMEFILE"
  `$DAYTCALC -t $NOW -x $LON -y $LAT -s $TZ -f > $DAYTIMEFILE`
fi

##########################################################
# Process the daily timelapse movie
##########################################################
 if [ -f $VARPATH/yesterday.mp4 ]; then
    echo "Found yesterdays timelapse movie."

    echo "Rotating the history of link pictures."
    if [ -f $IMGPATH/wcam6.png ]; then rm $IMGPATH/wcam6.png; fi
    if [ -f $IMGPATH/wcam5.png ]; then mv $IMGPATH/wcam5.png $IMGPATH/wcam6.png; fi
    if [ -f $IMGPATH/wcam4.png ]; then mv $IMGPATH/wcam4.png $IMGPATH/wcam5.png; fi
    if [ -f $IMGPATH/wcam3.png ]; then mv $IMGPATH/wcam3.png $IMGPATH/wcam4.png; fi
    if [ -f $IMGPATH/wcam2.png ]; then mv $IMGPATH/wcam2.png $IMGPATH/wcam3.png; fi
    if [ -f $IMGPATH/wcam1.png ]; then mv $IMGPATH/wcam1.png $IMGPATH/wcam2.png; fi

    echo "Extracting icon picture from yesterday.mp4."
    avconv -i $VARPATH/yesterday.mp4 -ss 00:00:15 -s 90x68 -vframes 1 -f image2 $IMGPATH/wcam1.png
    # timestamp image file to yesterday to let the webpage display correct date/day
    touch -t "$(date --date="-1 day" +"%Y%m%d2100")" $IMGPATH/wcam1.png

    echo "Rotating the history of timelapse movies."
    if [ -f $IMGPATH/wcam6.mp4 ]; then rm $IMGPATH/wcam6.mp4; fi
    if [ -f $IMGPATH/wcam5.mp4 ]; then mv $IMGPATH/wcam5.mp4 $IMGPATH/wcam6.mp4; fi
    if [ -f $IMGPATH/wcam4.mp4 ]; then mv $IMGPATH/wcam4.mp4 $IMGPATH/wcam5.mp4; fi
    if [ -f $IMGPATH/wcam3.mp4 ]; then mv $IMGPATH/wcam3.mp4 $IMGPATH/wcam4.mp4; fi
    if [ -f $IMGPATH/wcam2.mp4 ]; then mv $IMGPATH/wcam2.mp4 $IMGPATH/wcam3.mp4; fi
    if [ -f $IMGPATH/wcam1.mp4 ]; then mv $IMGPATH/wcam1.mp4 $IMGPATH/wcam2.mp4; fi
    mv $VARPATH/yesterday.mp4 $IMGPATH/wcam1.mp4
    touch -t "$(date --date="-1 day" +"%Y%m%d2100")" $IMGPATH/wcam1.mp4
fi
unset TZ
echo "rrdupdate.sh: End of script at `date`"
##########################################################
# End of rrdupdate.sh
##########################################################
