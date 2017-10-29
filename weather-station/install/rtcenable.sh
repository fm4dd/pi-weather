#!/bin/bash
##########################################################
# rtcenable.sh 20170624 Frank4DD
#
# This script enables a I2C RTC clock model DS3231.
# It runs once after clock installation.
#
# I am using Adafruit https://www.adafruit.com/product/3013/
#
# The script must be run as user "pi", it will use sudo
# if needed.
##########################################################
echo "rtcenable.sh: Enable I2C RTC clock model DS3231 at `date`"

echo "##########################################################"
echo "# 1. Find the RTC clock DS3231 on I2C bus 1, address 0x68"
echo "##########################################################"
i2cget -y 1 0x68
if [[ $? > 0 ]]; then
   echo "Error - cannot find RTC clock DS3231 on I2C bus 1" >&2
   exit 1
fi
echo "Found RTC clock DS3231 on I2C bus 1, address 0x68"
echo "Done."
echo

echo "##########################################################"
echo "# 2. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1;
fi
echo "OK, the user ID is [$EUID] = `whoami`"

echo "Done."
echo

echo "##########################################################"
echo "# 3. Enable RTC clock kernel support in /boot/config.txt"
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

GREP=`grep dtoverlay=i2c-rtc,ds3231 /boot/config.txt`

if [[ $? > 0 ]]; then
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /boot/config.txt"
   LINE2="# pi-weather: add support for DS3231 RTC clock"
   sudo sh -c "echo \"$LINE2\" >> /boot/config.txt"
   LINE3="dtoverlay=i2c-rtc,ds3231"
   sudo sh -c "echo \"$LINE3\" >> /boot/config.txt"
   echo "Adding 3 lines to /boot/config.txt file:"
   tail -4 /boot/config.txt
else
   echo "Found dtoverlay=i2c-rtc,ds3231 line in /boot/config.txt file:"
   echo "$GREP"
fi

echo "Done."
echo

echo "##########################################################"
echo "# 4. Remove the fake hardware clock from system"
echo "##########################################################"
echo "sudo apt-get -y remove fake-hwclock"
sudo apt-get -y remove fake-hwclock
echo "sudo update-rc.d -f fake-hwclock remove"
sudo update-rc.d -f fake-hwclock remove
echo "Done"
echo

echo "##########################################################"
echo "# 5. Update the /lib/udev/hwclock-set script"
echo "##########################################################"
if [ -f ../backup/$TODAY-hwclock-set.backup ]; then
   echo "Found existing backup of /lib/udev/hwclock-set file:"
   ls -l ../backup/$TODAY-hwclock-set.backup
else
   echo "Create new backup of current /lib/udev/hwclock-set file:"
   cp /boot/config.txt ../backup/$TODAY-hwclock-set.backup
   ls -l ../backup/$TODAY-hwclock-set.backup
fi

GREP=`egrep '#if [ -e /run/systemd/system ]' /lib/udev/hwclock-set`

if [[ $? > 0 ]]; then
   echo " Next, sudo vi /lib/udev/hwclock-set file and comment out below:"
   echo "#if [ -e /run/systemd/system ] ; then"
   echo "# exit 0"
   echo "#fi"
else
   echo "Found #if [ -e /run/systemd/system ] in /lib/udev/hwclock-set file:"
   echo "$GREP"
fi
echo "Done."
echo

echo "##########################################################"
echo "# 6. Test read from and write to the I2C hardware clock"
echo "##########################################################"
echo "sudo reboot # Reboot the system"
echo "sudo hwclock -D -r # -D is debug"
echo "sudo hwclock -w"
echo "sudo hwclock -r"

echo "##########################################################"
echo "# End of script rtcenable.sh."
echo "##########################################################"
