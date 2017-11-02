# Weather Display Software Package

## Background

The Pi-Weather Display is a Raspberry Pi A+ powered device for
permanently showing the outdoor weather data provided by the
Pi-Weather station. In its current design, it has a 20x4 Char
LCD screen for text output of date, temperature, humidity and
barometric pressure.

Additionally, a 5 inch TFT display connects through HDMI, and
shows the current data graphs vertically aligned. Both LCD and
TFT data is refreshed in 1 minute intervals, matching the data
collection frequency of the Raspberry Pi weather station.

It is equipped with a Adafruit TSL2561 light sensor to power
down the display at night, and wake it up with first light.

## 5 inch TFT screen component function

By default and out of the box, the TFT screen runs the Raspberry 
Pi commandline console. to display images, the "fbi" package has
been installed.

To display images on the TFT with the "fbi" program, see the
following example:

```sudo fbi --autozoom --noverbose --vt 1 out.png```

If it does not work try another vt terminal number, sometimes it
runs on 2. 

Raspbian runs multiple virtual terminals, they can be switched with
command "chvt".

The TFT screen can be turned off with command "tvservice -o", and
on with "tvservice -p". It seems more reliable to use the command 
"vcgencmd display_power 0" and "vcgencmd display_power 1".

For displaying a single picture with the "fbi" command, we need
to combine the separate graph pictures into a single image. This
can be done with the ImageMagick package. Using the "convert"
program, images can be aligned vertically, horizontally, clockwise,
embedding text or logos, etc. Its very powerful.

This is an example for aligning the 3 graph images into a single pic:

```convert \( daily_temp.png daily_humi.png daily_bmpr.png -append \) +append out.png```

## 20x4 character LCD component function

The 20x4 character LCD connects via a PCF8574 I2C-to-HD44780 LCD 
backpack module. Since the LCD is a 5V device while the Raspberry Pi
GPIO level is 3.3V, the PCA9306 I2C-bus 3.3-5V level converter
is in line. I am currently using a small python driver library for
writing to the LCD display. The driver is lightweight and only needs
installation of the " python-smbus" package.

## Component integration

Above display and sensor components are controlled though a main bash
script "display.sh", which in turn calls "lux" for reading the light
sensor, and sensor.py for parsing the raw weather data and displaying
it to the character LCD. 

## Power consumption

Daylight mode:	approx 760 ~ 830 mA
Nighttime mode: approx 360 ~ 410 mA

## TODO

Implement improved error handling to identify various conditions
such as Weather Station down, Wifi down, SCP error.

Build and integrate a push-button control panel to switch modes,
e.g. use the integrated I2C sensor GY-BME280 for indoor temperature
display mode.
