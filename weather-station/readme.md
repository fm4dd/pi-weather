# Pi Weather Station Software Package

This directory is tagged as a branch, to be cloned or copied into the weather stations Raspberry Pi OS. It contains the scripts for setup, upgrade and maintenance of weather station code and data. The weather station software is a mix of C programs and shell scripts. Data collection is using standard cron entries. RRD is used as the backend database.

## Directory Overview

weather-station/
 |
 +-- backup/ --> (empty) Used to store local configuration and data during software upgrades
 |
 +-- etc/ --> Contains the configuration template, which is the first file that needs to be edited.
 |
 +-- install/ -->Contains the scripts to create and upgrade the station software, or repair data.
 |
 +-- src/ --> Contains C source code for the station software. Compilation and install is done through setup.sh inside the install directory.
 |
 +-- web/ --> Contains the template files for the local website that runs on the weather station. The files are moved into place through setup.sh.

## Prerequisites

The weather stations Raspberry Pi's use Rasbian OS in the "lite" version, which fills the SD cards disk space to about 1.2 GB. The network should be configured for Internet access. The install process will get about 300 MB of additional required packages. The network connectivity can be either through Wifi or Ethernet, the weather station can work with either one.

Before I write the Rasbian OS image to SD card, I modify the image to add local network information, which lets me bring up the Pi into the local network and connect immediately at first boot. For modification, I mount the stock image file from a Linux VM as follows:

- Get file system layout

```
root@linvm:~ # fdisk -l 2017-04-10-raspbian-jessie-lite.img 
Disk 2017-04-10-raspbian-jessie-lite.img: 1.2 GiB, 1297862656 bytes, 2534888 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x84fa8189

Device                               Boot Start     End Sectors  Size Id Type
2017-04-10-raspbian-jessie-lite.img1       8192   92159   83968   41M  c W95 FAT32 (LBA)
2017-04-10-raspbian-jessie-lite.img2      92160 2534887 2442728  1.2G 83 Linux
```

- Mount the Linux partition by calculating its offset

```
root@linvm:~ # mount 2017-04-10-raspbian-jessie-lite.img -o loop,offset=$(( 512 * 92160)) /mnt
root@linvm:~ # ls /mnt/
```

- Update network and other configuration files

```
vi /mnt/etc/network/interfaces
vi /mnt/etc/wpa_supplicant/wpa_supplicant.conf
vi /mnt/etc/hosts
vi /mnt/etc/hostname
vi /mnt/etc/rsyslog.conf
vi /mnt/etc/modprobe.d/bcm2835_gpiomem.conf
umount /mnt
```

## Software Installation

First, create or update the configuration file `pi-weather.conf` in the `etc` directory. The following settings are minimum to be configured:

- *pi-weather-sid* --> Station ID that must be unique to each station. The value is used to set the hostname, and for data uploads to the centralized Internet website. The schema is pi-wsXX. XX is a two-digit number that is simply counted up.

- *pi-weather-lat* --> GPS latitude of the weather stations location. Value needs to be in decimal format.

- *pi-weather-lon* --> GPS longitude of the weather stations location. Decimal format.

- *pi-weather-tzs* --> Weather stations timezone setting (match entry in /usr/share/zoneinfo).

- *sensor-type=bme280* --> One of the supported sensor types.
*sensor-addr=0x76* --> The sensors I2C address.

Next, change directory into the `install` folder, and execute the script `setup.sh`. The script should run tests to confirm the sensor function. It creates the weather stations work directory named after the station ID, e.g. `pi-ws01`, containing the binaries and data directories.

## Local Station Operation

After completion, reboot the Pi. The weather station software installed a local web service (Lightttp) that allows pointing a browser to the stations IP address. The cron jobs should start collecting sensor data filling the RRD, and taking camera pictures in 1 minute intervals. Any issues can be investigated by looking at the files in `var` and `log` directories.

- Check the sensor data file existence and timestamp

```
pi@pi-ws01:~ $ ls -l pi-ws01/var/sensor.txt
-rw-r--r-- 1 pi pi 61 Oct 29 11:54 pi-ws01/var/sensor.txt
```

- Check the sensor data content

```
pi@pi-ws01:~ $ cat pi-ws01/var/sensor.txt
1509245646 Temp=14.83*C Humidity=91.26% Pressure=100555.85Pa
```

- Check the RRD database update log

```
pi@pi-ws01:~ $ cat pi-ws01/var/rrdupdate.log
rrdupdate.sh: Run at Sun 29 Oct 11:55:11 JST 2017
rrdupdate.sh: Config file [/home/pi/pi-ws01/bin/../etc/pi-weather.conf]
rrdupdate.sh: Sensor Data [1509245706 Temp=14.84*C Humidity=91.20% Pressure=100561.37Pa]
rrdupdate.sh: Temperature [14.84] outlier detection OK.
rrdupdate.sh: Humidity [91.20] outlier detection OK.
rrdupdate.sh: Pressure [100561.37] outlier detection OK.
rrdupdate.sh: daytime flag /home/pi/pi-ws01/bin/daytcalc -t 1509245706 -x 139.628999 -y 35.610381
rrdupdate.sh: daytcalc 1509245706 returned [0] [day].
/usr/bin/rrdtool update /home/pi/pi-ws01/rrd/weather.rrd 1509245706:14.84:91.20:100561.37:0
return_value = 0
[1509245700]RRA[AVERAGE][1]DS[temp] = 1.4839000000e+01
[1509245700]RRA[AVERAGE][1]DS[humi] = 9.1206000000e+01
[1509245700]RRA[AVERAGE][1]DS[bmpr] = 1.0056081800e+05
[1509245700]RRA[AVERAGE][1]DS[dayt] = 0.0000000000e+00
Creating image /home/pi/pi-ws01/web/images/daily_temp.png... 700x150
Creating image /home/pi/pi-ws01/web/images/daily_humi.png... 700x150
Creating image /home/pi/pi-ws01/web/images/daily_bmpr.png... 700x150
rrdupdate.sh: Finished Sun 29 Oct 11:55:12 JST 2017
```

## Integration with the Internet-based Web Server

The weather station is typically part of a private (home) network that allows only outbound Internet access. To access the weather stations data remotely, the station can be set to send its sensor and camera data to the central Internet web server (e.g. http://weather.fm4dd.com). The script `send-setup.sh` in the `install` directory collects the necessary information and copies it into the Internet server.

After the Internet web server has been set up, the sensor data is feed to Internet web server in parallel to the local RRD database updates. To compensate for temporary local network outages, a daily transmission sends the full RRD database to the Internet server. 

Because RRD databases are CPU-specific, they can't be copied from a Raspi (ARM) to an Intel environment. For RRD database mgrations, the `rrdtool dump` command creates a XML extract that can be restored to different platforms. For manal DB transmission, below commands serve as an example:

- Raspi side

```
pi@pi-ws01:~ $ rrdtool dump /home/pi/sensor/rrd/weather.rrd > weather.xml
pi@pi-ws01:~ $ scp weather.xml user@weather.fm4dd.com:~
```

- Internet server side

```
ws01@weatherweb:~ $ rrdtool restore /home/ws01/weather.xml pi-ws01.rrd
```

## Optional Hardware Setup

The script `rtcenable.sh` can enable an optional battery-buffered real-time clock module. The RTC is helpful for weather stations without permanent Internet access. If they are unable to sync their time from the net, they are at risk of running wrong system time, which in turn could break the sensor data collection.