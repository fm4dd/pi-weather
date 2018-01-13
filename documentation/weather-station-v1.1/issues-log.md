# Weather Station Version 1.1 Issue Log

## 1. RRD consolidation function is hard-coded to UTC

I whish RRD had the ability to specify a local timezone offset for the consolidation. 

For example, the weather station records temperature in 1-min intervals, kept for 10 days:

`DS:temp:GAUGE:300:-50:100 RRA:AVERAGE:0.5:1:14400`

For longterm data recording, the stations daily minimum and maximum temperature is kept for, say, 20 years:

`RRA:MIN:0.5:60:17568 RRA:MAX:0.5:60:17568`

With the highest resolution set to 1 minute, RRDtool loads the recorded temperatures in 1 minute intervals, using UTC timestamps. Displaying the 1-minute interval data in reference to a local time zone is no problem. The graph generation observes the timezone offset from UTC.

Now, lets say the days lowest temperature is 2°C, and gets recorded at 4:00 AM local time in a place having a timezone offset of -9 hrs (Japan JST). Because the RRD consolidation function occurs at midnight UTC, the consolidation happens at 9:00 AM JST.

This causes two issues: 

First, the previous day's Min/Max values do not become available at midnight local time, because the consolidation occurs at 9:00 AM local time the following day.

Second, the MIN value that was recorded at 4:00 AM local time gets consolidated with the timestamp using UTC, and because the consolidation happens at 9:00 AM, it will be assigned the UTC date instead of the local time date. In my example, the local timezone is 9 hours ahead of UTC, which means at the time the consolidation runs, our MIN value gets the UTC timestamp of the previous day instead. It is not possible to correct or compensate afterwards, because we no longer know the exact original timestamp of the Min value! This makes the consolidation meaningless under local timezone context.

Possible solutions:

**1)** Fake the initial 1-min UTC recording timestamps with an offset, e.g. by setting the system clock to local time instead of UTC.

This is a serious challenge, say if the weather stations get synced with GPS. It also causes other system issues, e.g  for log timestamps, and file copy, and for the individual weather station data consolidation to a central server. This also breaks the graph's background coloring for local nighttime, because its calculated from GPS locations sunset/sunrise time.

**2)** Implemented. In this workaround, I do not use the RRD consolidation for daily MIN/MAX values. Instead I expanded the lowest resolution range to 2 weeks, and implemented a search through the full RRD data set, which is coded outside of RRD. For monthly consolidation I still use the RRD function and accept the error for now. The chances are much lower that a MIN/MAX value occurs at the month's borders, but its still bothersome.

Ideal would be adding the option to specify a timezone to let RRD consolidation happen at midnight local time, observing UTC offset. Possibly even observe summertime adjustments. Weather data should always be seen in local context, local daytime/nighttime exposure to sunlight framing the temperature ranges.

For example:

`RRA:MIN:0.5:60:17568 RRA:MAX:0.5:60:17568` uses existing default UTC-based consolidation

`RRA:MIN:0.5:60:17568 RRA:MAX:0.5:60:17568:Asia/Tokyo` adding new option to specify a time zone, letting RRD calculate the offset to consolidate at local midnight instead of UTC.

## 2. RRD graphs nighttime background does not extend below zero if temperature becomes negative

I currently color the nighttime with a grey background, using the following expression:

<pre>  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \</pre>

The RRD value dayt stores the info about night (set to '1'), and day ('0'). If its 1, the area is shaded to grey (#cfcfcf) towards infinity (INF). It works great in summer, but wintertime brings temperatures below zero. The nighttime coloring continues to work, but starts at zero, leaving the area with the negative temperature at default white background.

Solution: Add a second area, stacked on top of the first, which adds below-zero coloring against negative infinity (NEGINF). 

<pre>  DEF:dayt1=$RRD:dayt:AVERAGE \
  'CDEF:dayt2=dayt1,0,GT,INF,UNKN,IF' \
  'AREA:dayt2#cfcfcf' \
  'CDEF:tneg1=dayt1,0,GT,NEGINF,UNKN,IF' \
  'AREA:tneg1#cfcfcf' \</pre>

Note 1: A conditional execution, e.g. shade second area only if temp < 0 is not needed, would complicate code without benefit.

Note 2: Initially I thought I would need 'AREA:tneg1#cfcfcf:STACK' to add onto the first area. This created problems because I got a legend entry for STACK. According to rrdtool documentation it should be 'AREA:tneg1#cfcfcf::STACK' with an extra colon, but that broke the second area which did not show at all. I just left it out, and that worked.
