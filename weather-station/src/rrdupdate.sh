#!/bin/bash
##########################################################
# rrdupdate.sh 20170624 Frank4DD
# 
# This script runs in 1-min intervals through cron. It
# it processes the independently generated sensor data file,
# updates the RRD database, and generates the graph images.
#
# It also handles the files that are created once per day:
# 1) generates the timelapse movie after midnight from
# previous days archived single webcam images
# 2) creates a RRD XML export file from the weather station
# and sends it to the web server (this helps filling any
# data gaps created by network outages).
#
# Please set config file path to your installations value!
##########################################################
sleep 10 # 10 sec past 00 to let send-data.sh update first
echo "rrdupdate.sh: Run at `date`"
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null
CONFIG=$SCRIPTPATH/../etc/pi-weather.conf
echo "rrdupdate.sh: Config file [$CONFIG]"

##########################################################
# RRDtool default parameters for graph image creation
# --slope-mode -> smoothens the default stair case curves
# --units-exponent=0 -->No y-axis value scaling (Kilo/Mega)
# this is only important for hPa not showing as 1.014k
##########################################################
GRAPH_PARAMS="
  --imgformat PNG
  --no-gridfit
  --slope-mode
  --width=1119
  --height=147
  --font AXIS:12:
  --font TITLE:15:
  --font LEGEND:14:
  --font WATERMARK:10:
  --units-exponent=0
  --border=1
  --color SHADEA#000000
  --color SHADEB#000000
"

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
  echo "rrdupdate.sh: Error - cannot find config file [$CONFIG]" >&2
  exit -1
fi
readconfig MYCONFIG < "$CONFIG"

RRD=${MYCONFIG[pi-weather-dir]}/rrd/${MYCONFIG[pi-weather-rrd]}
DAYTCALC="${MYCONFIG[pi-weather-dir]}/bin/daytcalc"
OUTLIER="${MYCONFIG[pi-weather-dir]}/bin/outlier"
MOMIMAX="${MYCONFIG[pi-weather-dir]}/bin/momimax"
IMGPATH="${MYCONFIG[pi-weather-dir]}/web/images"
WEBPATH="${MYCONFIG[pi-weather-dir]}/web"
VARPATH="${MYCONFIG[pi-weather-dir]}/var"
LOGPATH="${MYCONFIG[pi-weather-dir]}/log"
RRDTOOL="/usr/bin/rrdtool"

##########################################################
# Check if RRD database exists, exit if it doesn't
##########################################################
if [[ ! -e $RRD ]]; then
   echo "rrdupdate.sh: Error cannot find RRD database."
   exit 1
fi

##########################################################
# Check if sensor data file exists
##########################################################
if [[ ! -f $VARPATH/sensor.txt ]]; then
   echo "rrdupdate.sh: Error cannot find sensor data file."
else
   SENSORDATA=`cat $VARPATH/sensor.txt`;
   echo "rrdupdate.sh: Sensor Data [$SENSORDATA]"
fi

##########################################################
# Timestamp
##########################################################
TIME=`echo $SENSORDATA | cut -d " " -f 1`
if [ "$TIME" == "" ] || [ "$TIME" == "Error" ]; then
  echo "rrdupdate.sh: Error getting timestamp from sensor data"
  exit
fi

##########################################################
# Data Source 1: Temperature
##########################################################
TEMP=`echo $SENSORDATA | cut -d " " -f 2 | cut -c 6- | cut -d "*" -f 1`
if [ "$TEMP" == "" ]; then
  echo "rrdupdate.sh: Error getting temperature from sensor.txt"
  exit
fi

##########################################################
# Temperature outlier detection
##########################################################
LIMIT=5
$OUTLIER -s $RRD -d temp -n $TEMP -p $LIMIT
if [ $? == 1 ]; then
  echo "`date -R` [$SENSORDATA] -> temperature outlier [$TEMP]." >> $LOGPATH/outlier.log
  echo "rrdupdate.sh: Error temperature [$TEMP] is a outlier."
  TEMP=""
else
  echo "rrdupdate.sh: Temperature [$TEMP] outlier detection OK."
fi

##########################################################
# Data Source 2: Humidity
##########################################################
HUMI=`echo $SENSORDATA | cut -d " " -f 3 | cut -c 10- | cut -d "%" -f 1`
if [ "$HUMI" == "" ]; then
  echo "rrdupdate.sh: Error getting humidity from sensor.txt"
  exit
fi

##########################################################
# Humidity outlier detection
##########################################################
LIMIT=15
$OUTLIER -s $RRD -d humi -n $HUMI -p $LIMIT
if [ $? == 1 ]; then
  echo "`date -R` [$SENSORDATA] -> humidity outlier [$HUMI]." >> $LOGPATH/outlier.log
  echo "rrdupdate.sh: Error humidity [$HUMI] is a outlier."
  HUMI=""
else
  echo "rrdupdate.sh: Humidity [$HUMI] outlier detection OK."
fi

##########################################################
# Data Source 3: Pressure
##########################################################
BMPR=`echo $SENSORDATA | cut -d " " -f 4 | cut -c 10- | cut -d "P" -f 1`
if [ "$BMPR" == "" ]; then
  echo "rrdupdate.sh: Error getting pressure from sensor.txt"
  exit
fi

##########################################################
# Pressure outlier detection
##########################################################
LIMIT=12000
$OUTLIER -s $RRD -d bmpr -n $BMPR -p $LIMIT
if [ $? == 1 ]; then
  echo "`date -R` [$SENSORDATA] -> pressure outlier [$BMPR]." >> $LOGPATH/outlier.log
  echo "rrdupdate.sh: Error pressure [$BMPR] is a outlier."
  BMPR=""
else
  echo "rrdupdate.sh: Pressure [$BMPR] outlier detection OK."
fi

##########################################################
# Data Source 4: Daytime (TZ is taken from local system)
# ./daytcalc -t 1486784589 -x 12.45277778 -y 51.340277778
##########################################################
LON="${MYCONFIG[pi-weather-lon]}"
LAT="${MYCONFIG[pi-weather-lat]}"
DAYTIME=('day' 'night');

echo "rrdupdate.sh: daytime flag $DAYTCALC -t $TIME -x $LON -y $LAT"
`$DAYTCALC -t $TIME -x $LON -y $LAT`

DAYT=$?
if [ "$DAYT" == "" ]; then
  echo "rrdupdate.sh: Error getting daytime information, setting 0."
  DAYT=0
else
  echo "rrdupdate.sh: daytcalc $TIME returned [$DAYT] [${DAYTIME[$DAYT]}]."
fi

##########################################################
# write new data into the RRD DB
##########################################################
echo "$RRDTOOL update $RRD $TIME:$TEMP:$HUMI:$BMPR:$DAYT"
$RRDTOOL updatev $RRD "$TIME:$TEMP:$HUMI:$BMPR:$DAYT"

##########################################################
# Create the daily graph images
##########################################################
TEMPPNG=$IMGPATH/daily_temp.png
HUMIPNG=$IMGPATH/daily_humi.png
BMPRPNG=$IMGPATH/daily_bmpr.png

echo -n "Creating image $TEMPPNG... "
$RRDTOOL graph $TEMPPNG $GRAPH_PARAMS \
  --start -16h \
  --title='Temperature' \
  --step=60s  \
  DEF:temp1=$RRD:temp:AVERAGE \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \
  'CDEF:tneg1=dayt1,0,GT,NEGINF,UNKN,IF' \
  'AREA:tneg1#cfcfcf' \
  'CDEF:tminus=temp1,0.0,LE,temp1,UNKN,IF' \
  'CDEF:tplus=temp1,0.0,GE,temp1,UNKN,IF' \
  'AREA:tminus#004477:' \
  'AREA:tplus#99001F:Temperature in °C' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'

echo -n "Creating image $HUMIPNG... "
$RRDTOOL graph $HUMIPNG $GRAPH_PARAMS \
  --start -16h \
  --title='Relative Humidity' \
  --step=60s  \
  --upper-limit=100 \
  --lower-limit=0 \
  DEF:humi1=$RRD:humi:AVERAGE \
  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \
  'AREA:humi1#004477:Humidity in percent' \
  'GPRINT:humi1:MIN:Min\: %3.2lf' \
  'GPRINT:humi1:MAX:Max\: %3.2lf' \
  'GPRINT:humi1:LAST:Last\: %3.2lf'

echo -n "Creating image $BMPRPNG... "
$RRDTOOL graph $BMPRPNG $GRAPH_PARAMS \
  --start -16h \
  --title='Barometric Pressure' \
  --step=60s  \
  --alt-autoscale \
  --alt-y-grid \
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
if [ ! -f $MTEMPPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $MTEMPPNG... "

  # --------------------------------------- #
  # --x-grid defines the x-axis spacing.    #
  # format: GTM:GST:MTM:MST:LTM:LST:LPR:LFM #
  # GTM:GST base grid (Unit:How Many)       #
  # MTM:MST major grid (Unit:How Many)      #
  # LTM:LST how often labels are placed     #
  # --------------------------------------- #
  $RRDTOOL graph $MTEMPPNG $GRAPH_PARAMS \
  --start end-21d --end 00:00 \
  --title='Temperature, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  DEF:temp1=$RRD:temp:AVERAGE \
  'CDEF:tplus=temp1,0.0,GE,temp1,UNKN,IF' \
  'CDEF:tminus=temp1,0.0,LE,temp1,UNKN,IF' \
  'AREA:tplus#99001F:Temperature in °C' \
  'AREA:tminus#004477:' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if monthly humi file has already
# been updated today, otherwise generate.
##########################################################
if [ -f $MHUMIPNG ]; then FILEAGE=$(date -r $MHUMIPNG +%s); fi
if [ ! -f $MHUMIPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $MHUMIPNG... "

  $RRDTOOL graph $MHUMIPNG $GRAPH_PARAMS \
  --start end-21d --end 00:00 \
  --title='Relative Humidity, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --upper-limit=100 \
  --lower-limit=0 \
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
if [ ! -f $MBMPRPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $MBMPRPNG... "

  $RRDTOOL graph $MBMPRPNG $GRAPH_PARAMS \
  --start end-21d --end 00:00 \
  --title='Barometric Pressure, 3 Weeks' \
  --x-grid HOUR:8:DAY:1:DAY:1:86400:%d \
  --alt-autoscale \
  --alt-y-grid \
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
if [ ! -f $YTEMPPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $YTEMPPNG... "

  $RRDTOOL graph $YTEMPPNG $GRAPH_PARAMS \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Temperature, Yearly View' \
  DEF:temp1=$RRD:temp:AVERAGE \
  'CDEF:tplus=temp1,0,GE,temp1,UNKN,IF' \
  'CDEF:tminus=temp1,0,LE,temp1,UNKN,IF' \
  'AREA:tplus#99001F:Temperature in °C' \
  'AREA:tminus#004477:' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if yearly humi file has already
# been updated today, otherwise generate
##########################################################
if [ -f $YHUMIPNG ]; then FILEAGE=$(date -r $YHUMIPNG +%s); fi
if [ ! -f $YHUMIPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $YHUMIPNG... "

  $RRDTOOL graph $YHUMIPNG $GRAPH_PARAMS \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Relative Humidity, Yearly View' \
  --upper-limit=100 \
  --lower-limit=0 \
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
if [ ! -f $YBMPRPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $YBMPRPNG... "

  $RRDTOOL graph $YBMPRPNG $GRAPH_PARAMS \
  --start end-18mon --end 00:00 \
  --x-grid MONTH:1:YEAR:1:MONTH:1:2592000:%b \
  --title='Barometric Pressure, Yearly View' \
  --alt-autoscale \
  --alt-y-grid \
  --units-exponent=0 \
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
if [ ! -f $TWYTEMPPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $TWYTEMPPNG... "

  $RRDTOOL graph $TWYTEMPPNG $GRAPH_PARAMS \
  --start end-18years --end 00:00 \
  --x-grid YEAR:1:YEAR:10:YEAR:1:31536000:%Y \
  --title='Temperature, 18-Year View' \
  DEF:temp1=$RRD:temp:AVERAGE \
  'CDEF:tplus=temp1,0,GE,temp1,UNKN,IF' \
  'CDEF:tminus=temp1,0,LE,temp1,UNKN,IF' \
  'AREA:tplus#99001F:Temperature in °C' \
  'AREA:tminus#004477:' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'
fi

##########################################################
# Check if the 18-year humi file has already
# been updated today, otherwise generate it.
##########################################################
if [ -f $TWYHUMIPNG ]; then FILEAGE=$(date -r $TWYHUMIPNG +%s); fi
if [ ! -f $TWYHUMIPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $TWYHUMIPNG... "

  $RRDTOOL graph $TWYHUMIPNG $GRAPH_PARAMS \
  --start end-18years --end 00:00 \
  --x-grid YEAR:1:YEAR:10:YEAR:1:31536000:%Y \
  --title='Humidity, 18-Year View' \
  --upper-limit=100 \
  --lower-limit=0 \
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
if [ ! -f $TWYBMPRPNG ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating image $TWYBMPRPNG... "

  $RRDTOOL graph $TWYBMPRPNG $GRAPH_PARAMS \
  --start end-18years --end 00:00 \
  --x-grid YEAR:1:YEAR:10:YEAR:1:31536000:%Y \
  --title='Barometric Pressure, 18-Year View' \
  --alt-autoscale \
  --alt-y-grid \
  DEF:bmpr1=$RRD:bmpr:AVERAGE \
  'CDEF:bmpr2=bmpr1,100,/' \
  'AREA:bmpr2#007744:Barometric Pressure in hPa' \
  'GPRINT:bmpr2:MIN:Min\: %3.2lf' \
  'GPRINT:bmpr2:MAX:Max\: %3.2lf' \
  'GPRINT:bmpr2:LAST:Last\: %3.2lf'
fi

##########################################################
# Daily update of the 12-year Min/Max Temperature htm file
##########################################################
ALLHTMFILE=$WEBPATH/allmimax.htm

if [ -f $ALLHTMFILE ]; then FILEAGE=$(date -r $ALLHTMFILE +%s); fi
if [ ! -f $ALLHTMFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating $ALLHTMFILE... "
  $MOMIMAX -s $RRD -a $ALLHTMFILE
  cp $ALLHTMFILE $VARPATH/allmimax.htm
  echo " Done."
fi

##########################################################
# Daily update of the yearly Min/Max Temperature htm file
##########################################################
YEARHTMFILE=$WEBPATH/yearmimax.htm

if [ -f $YEARHTMFILE ]; then FILEAGE=$(date -r $YEARHTMFILE +%s); fi
if [ ! -f $YEARHTMFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating $YEARHTMFILE... "
  $MOMIMAX -s $RRD -y $YEARHTMFILE
  cp $YEARHTMFILE $VARPATH/yearmimax.htm
  echo " Done."
fi

##########################################################
# Daily update of the monthly Min/Max Temperature htm file
##########################################################
MONHTMFILE=$WEBPATH/momimax.htm

if [ -f $MONHTMFILE ]; then FILEAGE=$(date -r $MONHTMFILE +%s); fi
if [ ! -f $MONHTMFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating $MONHTMFILE... "
  $MOMIMAX -s $RRD -m $MONHTMFILE
  cp $MONHTMFILE $VARPATH/momimax.htm
  echo " Done."
fi

##########################################################
# Daily update of the 12-days Min/Max Temperature htm file
##########################################################
DAYHTMFILE=$WEBPATH/daymimax.htm

if [ -f $DAYHTMFILE ]; then FILEAGE=$(date -r $DAYHTMFILE +%s); fi
if [ ! -f $DAYHTMFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  echo -n "Creating $DAYHTMFILE... "
  $MOMIMAX -s $RRD -d $DAYHTMFILE
  cp $DAYHTMFILE $VARPATH/daymimax.htm
  echo " Done."
fi

##########################################################
# Daily update of the sunrise/sunset data file
##########################################################
DAYTIMEFILE=$WEBPATH/daytime.htm

if [ -f $DAYTIMEFILE ]; then FILEAGE=$(date -r $DAYTIMEFILE +%s); fi
if [ ! -f $DAYTIMEFILE ] || [[ "$FILEAGE" < "$midnight" ]]; then
  NOW=`date +%s`
  echo -n "Creating $DAYTIMEFILE... "
  `$DAYTCALC -t $NOW -x $LON -y $LAT -f > $DAYTIMEFILE`
  echo " Done."
fi

##########################################################
# Update  Raspberry Pi CPU temperature data
##########################################################
RPITEMP=`cat /sys/class/thermal/thermal_zone0/temp |  awk '{printf("%f", $1/1000)}'`
if [ "$RPITEMP" == "" ]; then
  echo "rrdupdate.sh: Error getting Raspberry Pi CPU temperature"
  exit
else
  echo "rrdupdate.sh: CPU temperature data: $RPITEMP"
fi

##########################################################
# write new temperature into the RPI Temperature RRD DB
##########################################################
RPIRRD=${MYCONFIG[pi-weather-dir]}/rrd/rpitemp.rrd
echo "$RRDTOOL update $RPIRRD $TIME:$RPITEMP"
$RRDTOOL updatev $RPIRRD "$TIME:$RPITEMP"

##########################################################
# Create the daily RPI CPU Temp
##########################################################
CTMPPNG=$IMGPATH/daily_ctmp.png

echo -n "Creating RPI CPU temp image $CTMPPNG... "
$RRDTOOL graph $CTMPPNG -a PNG \
  --start -16h \
  --title='Raspberry Pi CPU Temperature' \
  --step=60s  \
  --width=619 \
  --height=77 \
  --border=1  \
  --color SHADEA#000000 \
  --color SHADEB#000000 \
  DEF:temp1=$RPIRRD:temp:AVERAGE \
  'AREA:temp1#99001F:Temperature in °C' \
  'GPRINT:temp1:MIN:Min\: %3.2lf' \
  'GPRINT:temp1:MAX:Max\: %3.2lf' \
  'GPRINT:temp1:LAST:Last\: %3.2lf'

echo "rrdupdate.sh: Finished `date`"
##########################################################
# End of rrdupdate.sh
##########################################################
