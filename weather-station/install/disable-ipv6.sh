#!/bin/bash
##########################################################
# disable-ipv6.sh 20180404 Frank4DD
#
# This script disables IPv6 kernal and modules.
#
# The script must be run as user "pi", it will use sudo
# if needed.
##########################################################
echo "disable-ipv6.sh: Disable IPv6 at `date`"

echo "##########################################################"
echo "# 1. Check if this script runs as user "pi", not as root."
echo "##########################################################"
if (( $EUID != 1000 )); then
   echo "This script must be run as user \"pi\"."
   exit 1
fi
echo "OK, the user ID is [$EUID] = `whoami`"

echo "Done."
echo

echo "##########################################################"
echo "# 2. Disable the IPv6 module in /etc/modprobe.d/ipv6.conf"
echo "##########################################################"
FINDLINE="blacklist ipv6"

GREP=`grep "$FINDLINE" /etc/modprobe.d/ipv6.conf`
if [[ $? > 0 ]]; then
   echo "IPv6 module not yet disabled, update /etc/modprobe.d/ipv6.conf:"
   echo "Add 5 lines:"
   LINE1="##########################################################"
   sudo sh -c "echo \"$LINE1\" >> /etc/modprobe.d/ipv6.conf"
   LINE2="# pi-weather: turn off IPv6 module"
   sudo sh -c "echo \"$LINE2\" >> /etc/modprobe.d/ipv6.conf"
   LINE3="alias ipv6 off"
   sudo sh -c "echo \"$LINE3\" >> /etc/modprobe.d/ipv6.conf"
   LINE4="options ipv6 disable_ipv6=1"
   sudo sh -c "echo \"$LINE4\" >> /etc/modprobe.d/ipv6.conf"
   LINE5="blacklist ipv6"
   sudo sh -c "echo \"$LINE5\" >> /etc/modprobe.d/ipv6.conf"
   echo "Added below 4 lines to /etc/modprobe.d/ipv6.conf:"
else
   echo "Found IPv6-off line in /etc/modprobe.d/ipv6.conf:"
   echo "$GREP"
fi
tail -5 /etc/modprobe.d/ipv6.conf
echo "Done."
echo

echo "##########################################################"
echo "# End of script disable-ipv6.sh"
echo "##########################################################"
exit 0
