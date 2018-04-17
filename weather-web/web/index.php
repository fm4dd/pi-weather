<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link rel="stylesheet" type="text/css" href="/style.css" media="screen" />
<meta name="Title" content="Raspberry Pi Weather Station" />
<meta name="Description" content="Raspberry Pi Weather Station" />
<meta name="Keywords" content="Raspberry Pi, Weather Station, fm4dd.com" />
<meta name="Classification" content="Weather Station" />
<style type="text/css">
#content .icon, .map { height: 100px; width: 133px; margin-right: 10px; border: 1px solid #000000; }
#content .map {float: right; }
#content .sensordata { font-size: 12px; width: 114px; height: 20px; line-height: 20px; background-color: #CFCFCF; text-align: center; border: 1px solid #000000; }
#content .sensorvalue { font-size: 16px; font-weight: bold; display: inline-block; vertical-align: bottom; line-height: 20px; }
#content .sensorspace { width: 0px; }
#content .desc { float: right; margin-top: -12px; text-align: justify; }
#content .titleimg { float: left; height: 100px; width: 133px; margin-right: 10px; )
</style>
<title>Raspberry Pi Weather Station</title>
  <script type="text/javascript" src="http://maps.google.com/maps/api/js?sensor=false"></script>
  <script type="text/javascript"> function showMap(station, lat, lng) {
      var latlng = new google.maps.LatLng(lat, lng);
      var myOpts = { disableDefaultUI: true, zoom: 8, center: latlng, mapTypeId: google.maps.MapTypeId.TERRAIN };
      var map = new google.maps.Map(document.getElementById(station+"-map"), myOpts);
      var marker = new google.maps.Marker({position: latlng, map: map, title: station}); }
  </script>
</head>

<body>
<div id="wrapper">
<div id="banner">
<h1>Pi-Weather Station Online</h1>
<h2>Raspberry Pi local weather data collection system</h2>

</div>
<div id="vmenu">
  <ul>
    <li><a href="http://weather.fm4dd.com/" title="Weather Station Online"><span>Weather Online</span></a></li>
    <li><a href="http://fm4dd.com/" class="selected" title="FM4DD Site"><span>FM4DD Home</span></a></li>
    <li><a href="https://github.com/fm4dd/pi-weather" title="Weather Station Plans"><span>Github Docs</span></a></li>
  </ul>
</div>

<div id="content">
<p>
<div>
<div><img class="titleimg" src="https://github.com/fm4dd/sbc-benchmarks/raw/master/images/raspi3.png" /></div>
This site is the online frontend to Raspberry Pi powered weather stations. The <a href="https://www.raspberrypi.org/">Raspberry Pi</a> is a versatile, yet small-sized single-board computer made for embedded projects. When placed in a enclusure and coupled with environmental sensors, the recording of weather data over long periods of time becomes possible. This site acts as the online frontend to collect and visualize data from multiple weather stations.
<p>
To see individual station data, graphs and details, please klick on the station image below.
</div>
</p>
<?php
  function myscandir($dir, $exp, $how='name', $desc=0) { 
    $r = array(); 
    $dh = @opendir($dir); 
    if ($dh) { 
      while (($fname = readdir($dh)) !== false) { 
        if (preg_match($exp, $fname)) { 
          $stat = stat("$dir/$fname"); 
          $r[$fname] = ($how == 'name')? $fname: $stat[$how]; 
        } 
      } 
      closedir($dh); 
      if ($desc) { arsort($r); } 
      else { asort($r); } 
    } 
    return(array_keys($r)); 
  } 

  $r = myscandir('.', '/^pi-ws[0-9]{2}$/i', 'name', 0); 

  $conf = array();
  include("./common.php");
  foreach ($r as $station) {
    // If we want to skip a station, name it here:
    //if($station == "pi-ws03") continue;
    $conf = loadConfig($station, $station.".conf");
    // get the timezone
    $newTZ=trim($conf["pi-weather-tzs"]);
    $newTZ=str_replace('"', '', $newTZ);
    // get the GPS location
    $lat=trim($conf["pi-weather-lat"]);
    $lon=trim($conf["pi-weather-lon"]);
    // get the last file update time
    $now = time();
    if(file_exists("$station/getsensor.htm")) {         // check if file exists
      date_default_timezone_set(UTC);
      $sensorts = filemtime("$station/getsensor.htm");  // get file modification time
      $dt = new DateTime();                             // create new Date object
      $dt->setTimestamp($sensorts);                     // set Date object to tstamp
      $output = "Last Station update received ";
      $output = $output.$dt->format('l F j Y, H:i:s T'); // format output string
    }
    else $ouptut = "Could not read last update time from $station/getsensor.htm";
    // Uptime: raspidat.htm -<tr><td>26d:18h:47m:44s</td></tr>
    $datfile = file_get_contents("$station/raspidat.htm");
    $pattern = '/[0-9]{1,3}d:[0-9]{1,2}h:[0-9]{1,2}m/';
    preg_match( $pattern, $datfile, $uptime);
    $rrd = getRRD($station);
    $tstamp = filemtime("$station");
    $dt->setTimestamp($tstamp);                       // set Date object to tstamp
    $first = $dt->format('M j Y');
    // Check the station is active, e.g. data not older than 10 mins
    $activestr = "(<span style=\"color: #99001F\">Inactive</span>)";
    if (($now - $sensorts) <= 600) $activestr = "(<span style=\"color: #007744\">Active</span>)";


    print "<div class=\"copyright\">$output</div>";
    print "<h3>$station $activestr</h3>\n";
    print "<hr />\n";
    print "<div class=\"desc\">\n";
    include("$station/getsensor.htm");
    print "<table><tr>\n";
    print "<td class=\"sensordata\">Station Timezone:<span class=\"sensorvalue\">$newTZ</span></td>\n";
    print "<td class=\"sensorspace\"></td>\n";
    print "<td class=\"sensordata\">Station Uptime:<span class=\"sensorvalue\">$uptime[0]</span></td>\n";
    print "<td class=\"sensorspace\"></td>\n";
    print "<td class=\"sensordata\">Reporting Since:<span class=\"sensorvalue\">$first</span></td>\n";
    print "</tr></table>\n";
    print "</div>\n";
    print "<div>\n";
    print "<a href=\"$station\">";
    print "<img class=\"icon\" src=\"$station/images/raspicam.jpg\" alt=\"$station live image\" />\n";
    print "</a>";
    print "<div class=\"map\" id=\"$station-map\"></div>";
    print "</div>\n";
    print "<script type=\"text/javascript\">showMap(\"$station\", $lat, $lon);</script>";
  }
?> 
<p>
For more information, contact support[at]frank4dd.com.
</div>

<div id="sidecontent">
<?php
?>
    <p>
    <script type="text/javascript"><!--
      google_ad_client = "pub-6688183504093504";
      /* Opensource Software 120x600 */
      google_ad_slot = "0003115987";
      google_ad_width = 120;
      google_ad_height = 600;
      //-->
    </script>
    <script type="text/javascript"
      src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
    </script>
    </p>
  </div>

  <div id="footer">
    <span class="left">&copy; 2017, FM4DD.com</span>
    <span class="right">Raspberry Pi - running Raspbian</span>
  </div>
</div>
</body>
</html>
