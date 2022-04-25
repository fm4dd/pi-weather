#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
##########################################################
# sensor.py 20170930 Frank4DD
# updated 20220425 for JSON data retrieval over HTTP
# This python3 script manages the 20x4 character LCD
# in combination with the I2C_LCD_driver.py driver.
########################################################
"""
import time
import I2C_LCD_driver
from time import *
import urllib.request
import json

sensor_data = urllib.request.urlopen("http://192.168.11.244/getsensor.json").read().decode('utf-8')
#print(sensor_data)
sensor_obj = json.loads(sensor_data)
local_time = localtime(sensor_obj["time"])
timestr = strftime("%D %H:%M", local_time)
line1 = "Date: " + timestr;
line2 = "Temp. "+'\xDF'+"C: " + "{0:.2f}".format(sensor_obj["temp"]) + '\xDF'+ "C"
line3 = "Humidity: " + "{0:.2f}".format(sensor_obj["humi"]) + "%"
line4 = "Pressure: " + "{0:.2f}".format(sensor_obj["pres"]/100) + "hPa"
#print(line1)
#print(line2)
#print(line3)
#print(line4)
mylcd = I2C_LCD_driver.lcd()
mylcd.lcd_display_string(line1, 1)
mylcd.lcd_display_string(line2, 2)
mylcd.lcd_display_string(line3, 3)
mylcd.lcd_display_string(line4, 4)
