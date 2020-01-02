#!/bin/bash
##################################################################
# A Project of TNET Services, Inc
#
# Title:     wifi-check.sh
# Author:    Kevin Reed (Dweeber)
#            dweeber.dweebs@gmail.com
# Project:   Raspberry Pi Stuff
#
# Copyright: Copyright (c) 2012 Kevin Reed <kreed@tnet.com>
#            https://github.com/dweeber/WiFi_Check
#            https://gist.github.com/mharizanov/5325450
#
# Purpose:   Check if WiFi is up has an IP, or restart Interface
#
# Uses a lock file to prevent the script from running more than
# once.  If lockfile is old, it gets removed.
#
# Instructions:
#
# o Install where you want to run it, e.g. /usr/local/bin
# o chmod 0755 /usr/local/bin/wifi-check.sh
# o Add to crontab
#
# Run once every 2-5 mins */5 or */2, e.g.
#
# */5 * * * * /srv/scripts/wifi-check.sh
#
##################################################################
# Settings
# Where and what you want to call the Lockfile
lockfile='/var/run/WiFi_Check.pid'

# Which Interface do you want to check/fix
wlan='wlan0'
pingip='192.168.179.1'

##################################################################
echo
echo "Starting WiFi check for $wlan"
date
echo

# Check to see if there is a lock file
if [ -e $lockfile ]; then
    # A lockfile exists... Lets check to see if it is still valid
    pid=`cat $lockfile`
    if kill -0 &>1 > /dev/null $pid; then
        # Still Valid... lets let it be...
        #echo "Process still running, Lockfile valid"
        exit 1
    else
        # Old Lockfile, Remove it
        #echo "Old lockfile, Removing Lockfile"
        rm $lockfile
    fi
fi

# If we get here, set a lock file using our current PID#
#echo "Setting Lockfile"
echo $$ > $lockfile

# We can perform check
echo "Performing Network check for $wlan"
/bin/ping -c 2 -I $wlan $pingip > /dev/null 2> /dev/null

if [ $? -ge 1 ] ; then
    echo "Network connection down! Attempting reconnection."
    /sbin/ifdown $wlan
    /bin/sleep 5
    /sbin/ifup --force $wlan
else
    echo "Network is Okay"
fi

echo
echo "Current Setting:"
/sbin/ifconfig $wlan | grep "inet"
echo

# Check is complete, Remove Lock file and exit
#echo "process is complete, removing lockfile"
rm $lockfile
exit 0
##################################################################
# End of Script
##################################################################
