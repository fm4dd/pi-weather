#!/bin/bash
##########################################################
# powersave.sh 20170624 Frank4DD
#
# This script enables power saving options: disable HDMI,
# PWR and ACT LED lights. It runs once during setup, and
# modifies the boot config.
#
# The script must be run as user "pi", it will use sudo
# if needed.
##########################################################
echo "powersave.sh: Enable power saving options at `date`"

echo "##########################################################"
echo "# 1. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1;
fi
echo "OK, the user ID is [$EUID] = `whoami`"

echo "Done."
echo

echo "##########################################################"
echo "# 2. Disable the HDMI port (saves about 25 mA)"
echo "##########################################################"
HDMIOFF="/usr/bin/tvservice -o"

GREP=`grep "$HDMIOFF" /etc/rc.local`
if [[ $? > 0 ]]; then
   echo "HMDI not yet disabled, update /etc/rc.local:"
   echo "Remove last line exit 0, we re-add it later."
   sudo tail -n 1 /etc/rc.local | tee >(wc -c | xargs -I {} sudo truncate /etc/rc.local -s -{})

   echo "Now add 4 lines to /etc/rc.local:"
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/rc.local"
   LINE2="# pi-weather: turn off HDMI, status /usr/bin/tvservice -s"
   sudo sh -c "echo \"$LINE2\" >> /etc/rc.local"
   LINE3=$HDMIOFF
   sudo sh -c "echo \"$LINE3\" >> /etc/rc.local"
   LINE4="exit 0"
   sudo sh -c "echo \"$LINE4\" >> /etc/rc.local"
   echo "Added below 4 lines to /etc/rc.local file:"
   tail -4 /etc/rc.local
else
   echo "Found HDMI-off line in /etc/rc.local file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 3. Disable the ACT LED in /boot/config.txt"
echo "##########################################################"
TODAY=`date +'%Y%m%d'`
if [ -f ../backup/$TODAY-bootconfig.backup ]; then
  echo "Found existing backup of /boot/config.txt file:"
  ls -l ../backup/$TODAY-bootconfig.backup
else
  echo "Create new backup of current /boot/config.txt file:"
  cp /boot/config.txt ../backup/$TODAY-bootconfig.backup
  ls -l ../backup/$TODAY-bootconfig.backup
fi
echo

GREP=`grep dtparam=act_led_activelow=off /boot/config.txt`

if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /boot/config.txt"
   LINE2="# pi-weather: Disable the ACT LED."
   sudo sh -c "echo \"$LINE2\" >> /boot/config.txt"
   LINE3="dtparam=act_led_trigger=none"
   sudo sh -c "echo \"$LINE3\" >> /boot/config.txt"
   LINE4="dtparam=act_led_activelow=off"
   sudo sh -c "echo \"$LINE4\" >> /boot/config.txt"

   echo "Adding 4 lines to /boot/config.txt file:"
   tail -4 /boot/config.txt
else
   echo "Found dtparam=act_led_activelow=off line in /boot/config.txt file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 4. Disable the PWR LED in /boot/config.txt"
echo "##########################################################"

GREP=`grep dtparam=pwr_led_activelow=off /boot/config.txt`

if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /boot/config.txt"
   LINE2="# pi-weather: Disable the PWR LED."
   sudo sh -c "echo \"$LINE2\" >> /boot/config.txt"
   LINE3="dtparam=pwr_led_trigger=none"
   sudo sh -c "echo \"$LINE3\" >> /boot/config.txt"
   LINE4="dtparam=pwr_led_activelow=off"
   sudo sh -c "echo \"$LINE4\" >> /boot/config.txt"

   echo "Adding 4 lines to /boot/config.txt file:"
   tail -4 /boot/config.txt
else
   echo "Found dtparam=pwr_led_activelow=off line in /boot/config.txt file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 5. On a Raspberry Pi 3, we underclock 1.2 GHz to 900 MHz"
echo "##########################################################"

PI3=0
GREP=`grep BCM2709 /proc/cpuinfo`

if [[ $? == 0 ]]; then
   echo "Detected CPU type BCM2709 in /proc/cpuinfo:"
   echo "$GREP"
   PI3=1
else
   echo "Could not find CPU type BCM2709 in /proc/cpuinfo:"
   echo "$GREP"
fi
echo

GREP=`grep arm_freq=900 /boot/config.txt`
RET=$?

if [ "$PI3" == "1" ] && [ "$RET" != "0" ]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /boot/config.txt"
   LINE2="# pi-weather: Underclock the Pi-3 to reduce power and heat"
   sudo sh -c "echo \"$LINE2\" >> /boot/config.txt"
   LINE3="arm_freq=900"
   sudo sh -c "echo \"$LINE3\" >> /boot/config.txt"
   LINE4="arm_freq_min=600"
   sudo sh -c "echo \"$LINE4\" >> /boot/config.txt"

   echo "Adding 4 lines to /boot/config.txt file:"
   tail -4 /boot/config.txt
else
   echo "Found 900 MHz line in /boot/config.txt file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# End of script powersave.sh."
echo "##########################################################"
exit 0
