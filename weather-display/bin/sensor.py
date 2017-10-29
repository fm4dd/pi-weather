#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
##########################################################
# sensor.py 20170930 Frank4DD
#
# This python script manages the 20x4 character LCD
# in combination with the I2C_LCD_driver.py driver.
# 
# It first gets the environmental light from the TSL2561
# sensor, and considers brightness to switch the LCD on.
#
# If brightness is above 1 lux, extract the sensor.txt
# weatherstation raw data and output it to the LCD.
########################################################
"""
import time
import subprocess
import I2C_LCD_driver
from time import *

homedir = "/home/pi/pi-display"
tsl2561 = homedir + "/bin/lux"

lux = subprocess.call([tsl2561])

if lux < 1:
    mylcd = I2C_LCD_driver.lcd()
    mylcd.backlight(0)
else:
    mylcd = I2C_LCD_driver.lcd()
    sensor  = homedir + "/var/sensor.txt"
    with open(sensor, 'r') as f:
        data = f.readline().strip()

    values = data.split(" ")

    tstamp  = int(values[0])
    local_time = localtime(tstamp)
    timestr = strftime("%D %H:%M", local_time)

    tempstr = values[1]
    humistr = values[2]
    bmprstr = values[3]

    temp = tempstr.split("=")
    humi = humistr.split("=")
    bmpr = bmprstr.split("=")

    bmpr = bmpr[1].rpartition('P')[0]
    bmpr = float(bmpr)
    bmpr = bmpr/100


    line1 = timestr + " " + str(lux) + "Lux"
    line2 = "Temp. "+'\xDF'+"C: "+temp[1]
    line3 = "Humidity: "+humi[1]
    line4 = "Pressure: "+"%.2fhPa" % bmpr

    mylcd.lcd_display_string(line1, 1)
    mylcd.lcd_display_string(line2, 2)
    mylcd.lcd_display_string(line3, 3)
    mylcd.lcd_display_string(line4, 4)
