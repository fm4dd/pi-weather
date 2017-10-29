# Weather Station Version 1.0 Issue Log

## 1. Pi crash due to syslog data stuck in the xconsole pipe.

See also https://www.raspberrypi.org/forums/viewtopic.php?f=91&t=122601

Solution: Comment out last 4 lines in /etc/rsyslogd.conf:

```
#daemon.*;mail.*;\
#       news.err;\
#       *.=debug;*.=info;\
#       *.=notice;*.=warn       |/dev/xconsole
```

## 2. Extensive logs from cron execution

The seansor data aquisition is done through cron-controlled scripts in 1-minute intervals. Cron created a log entry each time it runs, which leads to excessive wear and logfile growth.

**Solution:** Turn off cron logging by setting `EXTRA_OPTS="-L 0"` in /etc/default/cron

## 3. Reading sensor data creates unnecessary GPIO access log records

Log example:
`Feb 26 14:56:08 raspi2 kernel: [  326.361596] gpiomem-bcm2835 3f200000.gpiomem: gpiomem device opened.`

**Solution 1:** Filter the log message in /etc/rsyslog.conf by setting the following rule as the first entry:
```
#
# Here we supress the gpio messages from reading sensor data
#
:msg, contains, "gpiomem-bcm2835 3f200000.gpiomem: gpiomem device opened." stop
```

**Solution 2:** Disable `CONFIG_DYNAMIC_DEBUG` by modprobe options

```
vi /etc/modprobe.d/bcm2835_gpiomem.conf
...
options bcm2835_gpiomem dyndbg=-p
```

save and reboot.

## 4. Micro SD Card Failure

**Solution 1:** Installation of a backup USB stick (dev/sda1), together with a weekly backup script that creates backups of package list, configuration files, data and script directories.

**Solution 2:** Selection of a reliable brand SD card with sufficient free space for wear-levelling. Standardizing on Samsung model MB-MC64DA microSDXC 64GB EVO+ Class10 UHS-I.

MB-MC64DA	Samsung microSDXC 64GB EVO+ Class10 UHS-I (21 MB/s Windows write speed)
```
Disk /dev/mmcblk0: 59.6 GiB, 64021856256 bytes, 125042688 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x0d1eadf0
```
```
Device         Boot  Start       End   Sectors  Size Id Type
/dev/mmcblk0p1        8192    137215    129024   63M  c W95 FAT32 (LBA)
/dev/mmcblk0p2      137216 125042687 124905472 59.6G 83 Linux
```

Substitute models:

MB-MC64GA/ECO	Samsung microSDXC 64GB EVO Plus Class10 UHS-I U3 (52 MB/s Windows write speed)
```
Disk /dev/mmcblk0: 59.6 GiB, 64021856256 bytes, 125042688 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xafe031c2
```
```
Device         Boot Start       End   Sectors  Size Id Type
/dev/mmcblk0p1       8192     92159     83968   41M  c W95 FAT32 (LBA)
/dev/mmcblk0p2      92160 125042687 124950528 59.6G 83 Linux
```



MB-MD64GA Samsung microSDXC 64GB PRO+ Class10 UHS-I U3 (90 MB/s Windows write speed)
```
Disk /dev/mmcblk0: 59.6 GiB, 64021856256 bytes, 125042688 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xaaa6313d
```
```
Device         Boot  Start       End   Sectors  Size Id Type
/dev/mmcblk0p1       49152    253951    204800  100M 83 Linux
/dev/mmcblk0p2      253952 125042687 124788736 59.5G 83 Linux
```
