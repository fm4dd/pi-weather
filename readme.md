# Pi-Weather

An outdoor weather station build around the Raspberry Pi

<img src="documentation\weather-station-v1.0\images\weather-station-v10-11.jpg" style="height: 160px; margin-right: 20px"><img src="documentation\weather-station-v1.0\images\weather-station-v10-10.jpg" style="height: 160px; width: 120px; margin-right: 20px"><img src="documentation\weather-station-v1.1\images\weather-station-v11-02.jpg" style="height: 160px; width: 120px; margin-right: 20px"><img src="documentation\weather-display-v1.0\images\weather-display-v10-05.jpg" style="height: 160px; margin-right: 10px">

This project contains the physical build documentation and software for running a Raspberry Pi powered outdoor weather station. With the rise of small form factor single board computers coupled with affordable sensors, monitoring of weather parameters like temperature, humidity, and air pressure allows for longterm observation, data logging and trending.

## Live Weather URL

The weather station started to work in September 2016, and its data can be seen live at <a href="http://weather.fm4dd.com/">http://weather.fm4dd.com/</a>. Besides showing actual data data readings, the weather data is presented as a graph over time. For example, the temperature data graph looks like this:

<img src="documentation\weather-station-v1.1\images\graph-example-temp1.png">

## Project Goals

Weather is defined as the temporary, day-to-day, minute-to-minute state of the atmosphere at a specific time and place. It is characterized by the interaction of several physical variables in the lower atmosphere (troposphere), which is constantly changing. The primary physical weather characteristics are:
* **Temperature**: Describes how hot or cold the air is, influenced by solar radiation and heat absorption.
* **Atmospheric Pressure**: The weight of the air above a given point. High pressure indicates clear skies, low pressure unsettled, cloudy, or stormy weather.
* **Wind**: The movement of air caused by differences in pressure, characterized by both speed and direction.
* **Humidity**: The amount of water vapor in the air, expressed as relative humidity, the percentage of water vapor relative to the maximum.
* **Precipitation**: Water in liquid or solid form falling from the sky as rain, snow, sleet, or hail.
* **Clouds**: Visible masses of water droplets or ice crystals suspended in the atmosphere, precursor to eventual precipitation.
* **Visibility**: The distance at which objects can be seen, which is reduced by fog, rain, or snow.

Based on available sensors, this weather station collects 3 input values, recording **Temperature**, **Atmospheric Pressure**, and **Humidity**. Because **Temperature** is strongly impacted by solar radiation, a **"Daylight"** flag based on sunrise/sunset times for the specific location provides the reference tho visualize daytime/nightime temperature ranges.

## High-level Design

Building a weather station around a Raspberry Pi allows to create a system that can long-term operate stand-alone, and has enough CPU power process environmental images in addition to sensor data. The built-in network stack can send collected data into a central consolidation site, and electrical power needs are still within range for small scale solar power. A waterproof switchbox protects the Raspberry, and a wood frame mounts the sensors together with the Raspberry Pi camera.

The <a href="documentation">documentation</a> directory has hardware BOM and CAD drawings to build the weather station and the weather display.

The necessary software can be cloned from the branches for the <a href="weather-station">weather station</a>, the optional <a href="weather-display">weather display</a>, and for the Internet accessible <a href="weather-web">website</a> that consolidates multiple weather stations from various time zones. Each weather station can operate "standalone" and self-contained, without needign to connect to a central portal.

The environmental weather data is collected through a Bosch BME280 sensor, connected to the RaspBerry Pi GPIO terminal, using the I2C bus.

## RRD Database

Sensor data is written in 1-minute intervals to an RRD database named `weather.rrd`. This database has been designed for 20 years longterm trending. It has the following parameters:

### 1. Data Source (DS) Configuration
These are the input variables stored in the database:

| DS Name | Index | Type | Min Value | Max Value | Heartbeat | Description |
| :--- | :---: | :--- | :---: | :---: | :---: | :--- |
| **temp** | 0 | GAUGE | -100 | 100 | 300s | Temperature |
| **humi** | 1 | GAUGE | 0 | 100 | 300s | Humidity (%) |
| **bmpr** | 2 | GAUGE | 0 | 200,000 | 300s | Barometric Pressure |
| **dayt** | 3 | GAUGE | 0 | 1 | 300s | Daylight Flag (Boolean) |

### 2. Round Robin Archive (RRA) Configuration
These are the retention settings, showing how data is consolidated and how long it is retained:

| RRA | Consolidation (CF) | Steps (PDP) | Resolution | Rows | Retention Period |
| :--- | :--- | :---: | :--- | :---: | :--- |
| **0** | AVERAGE | 1 | 1 Minute | 20,160 | 14 Days |
| **1** | AVERAGE | 60 | 1 Hour | 17,568 | 2 Years |
| **2** | AVERAGE | 1440 | 1 Day | 7,320 | 20 Years |
| **3** | MIN | 60 | 1 Hour | 17,568 | 2 Years |
| **4** | MAX | 60 | 1 Hour | 17,568 | 2 Years |
| **5** | MIN | 1440 | 1 Day | 7,320 | 20 Years |
| **6** | MAX | 1440 | 1 Day | 7,320 | 20 Years |

### 3. Database Characteristics

#### Data Integrity & Heartbeat:

The `minimal_heartbeat` is set to **300s** (5 minutes). With a base step of 60 seconds, the database will tolerate up to 4 consecutive missing updates. If no data is received for 5 minutes (5), the entry will be recorded as `UNKNOWN` (NaN).

All archives use an Consolidation Threshold `xff` of **0.5**. This is called the xfiles factor, and means that as long as at least 50% of the primary data points in a given interval are known, the consolidated archive entry will be calculated; otherwise, it will be stored as `UNKNOWN`.

#### High Resolution:

With a base step of **60 seconds**, the database keeps 1-minute granular data for exactly **14 days** (20,160 rows) in RRA 0.

#### Long-Term History:

The daily archives (RRA 2, 5, 6) are configured to retain data for **20 years** (7,320 rows), making this schema ideal for long-term climate trend analysis.

#### Statistical Tracking:

The schema tracks not only the **AVERAGE** values but also the **MIN** and **MAX** values for hourly and daily intervals. This prevents "averaging out" extreme weather events (like temperature spikes or pressure drops) in long-term logs.

#### Database Size:

The database uses 3MB disk space.

```
pi@pi-ws01:~ $ du -sh /home/pi/pi-ws01/rrd/weather.rrd
2.9M    /home/pi/pi-ws01/rrd/weather.rrd
```
The xml extracted database dump is 13MB.
```
pi@pi-ws01:~ $ du -sh /tmp/tmp.xml
13M     /tmp/tmp.xml
```
