# Pi-Weather

An outdoor weather station build around the Raspberry Pi

<img align="left" src="documentation\weather-station-v1.0\images\weather-station-v10-10.jpg" height="160px" width="120px"><img align="left" src="documentation\weather-station-v1.1\images\weather-station-v11-02.jpg" height="160px" width="120px"><img src="documentation\weather-display-v1.0\images\weather-display-v10-05.jpg" height="160x" width="213px">

This project contains the physical build documentation and software for running a Raspberry Pi powered outdoor weather station. With the rise of small form factor single board computers coupled with affordable sensors, monitoring of weather parameters like temperature, humidity, and air pressure allows for longterm observation, data logging and trending.

## Live Weather URL

The weather station started to work in September 2016, and its data can be seen live at <a href="http://weather.fm4dd.com/">http://weather.fm4dd.com/</a>

## Design

<img align="left" src="documentation\weather-station-v1.0\images\weather-station-v10-11.jpg" height="160px" width="160px">

Building a weather station around a Raspberry Pi allows to create a system that can long-term operate stand-alone, and has enough CPU power process environmental images in addition to sensor data. The built-in network stack can send collected data into a central consolidation site, and electrical power needs are still within range for small scale solar power. A waterproof switchbox protects the Raspberry, and a wood frame mounts the sensors together with the Raspberry Pi camera.

## Getting Started

The [documentation] (../tree/master/documentation) directory has the hardware BOM and CAD drawings to build the weather station and the weather display.

The necessary software can be cloned from the branches for the weather station [link] (../tree/master/weather-station), the optional weather display [link] (../tree/master/weather-display), and for the Internet accessible website [link] (../tree/master/weather-web) that consolidates multiple weather stations from various time zones.

## Operations and Todo

As with every new projects, not everything turns out as planned. Problems occur that need further improvement. The Wiki pages are good for keeping track.

