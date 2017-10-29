<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link rel="stylesheet" type="text/css" href="style.css" media="screen" />
<meta name="Title" content="Raspberry Pi Weather Station" />
<meta name="Description" content="Raspberry Pi Weather Station" />
<meta name="Keywords" content="Raspberry Pi, Weather Station, fm4dd.com" />
<meta name="Classification" content="Weather Station" />
<style type="text/css">
</style>
<title>Raspberry Pi Weather Station</title>
<script>
  function elementHideShow(element) {
    var el = document.getElementById(element);
    if (el.style.display == "block") { el.style.display = "none"; }
    else { el.style.display = "block"; }
  }
</script>
</head>

<body>
<div id="wrapper">
<div id="banner">
<h1>Pi-Weather Station <?php echo gethostname() ?></h1>
<h2>Raspberry Pi local weather data collection system</h2>

</div>
<div id="vmenu">
  <ul>
    <li><a href="index.php" class="selected" title="Weather Station Data"><span>Station Data</span></a></li>
    <li><a href="showlog.php" title="Weather Station Logs"><span>Station Logs</span></a></li>
    <li><a href="phpinfo.php" title="Weather Station PHP info"><span>Station PHP info</span></a></li>
    <li><a href="http://weather.fm4dd.com/" title="Weather Station Online"><span>Weather Online</span></a></li>
    <li><a href="http://fm4dd.com/" class="selected" title="FM4DD Site"><span>FM4DD Home</span></a></li>
    <li><a href="https://github.com/fm4dd/pi-weather" title="Weather Station Plans"><span>Github Docs</span></a></li>
  </ul>
</div>

<div id="content">

<?php if(file_exists("images/raspicam.jpg")) {      // check if file exists
  $tstamp = filemtime("images/raspicam.jpg");       // get file modification time
  $dt = new DateTime();                             // create new Date object
  $dt->setTimeStamp($tstamp);                       // set Date object to tstamp
  $output = $dt->format('l F j Y,  H:i:s');         // format output string
  echo "<h3>Webcam View: $output</h3>\n";
  echo "<hr />\n";
  echo "<div class=\"frame\">\n";
  echo "<img class=\"weatherpic\" src=\"images/raspicam.jpg\" alt=\"raspi weather camera\" />\n";
  echo "</div>\n";
}

  if(file_exists("getsensor.htm")) {                // check if file exists
  $tstamp = filemtime("getsensor.htm");             // get file modification time
  $dt = new DateTime();                             // create new Date object
  $dt->setTimestamp($tstamp);                       // set Date object to tstamp
  $output = $dt->format('l F j Y, H:i:s');          // format output string
  echo "<h3>Sensor Data: $output ";
  include("./daytime.htm");
  echo "</h3>\n";
} ?>

<hr />
<?php include("./getsensor.htm"); ?>
<div class="fullgraph"><img src="images/daily_temp.png" alt="Current Temperature Graph"></div>
<div class="fullgraph"><img src="images/daily_humi.png" alt="Current Humidity Graph"></div>
<div class="fullgraph"><img src="images/daily_bmpr.png" alt="Current Pressure Graph"></div>
<div class="copyright"><a href="javascript:elementHideShow('weekly');">Expand or Hide Shortterm Details</a></div>
<h3>Shortterm View:</h3>
<hr />
<div class="showext" id="weekly" style="display: none;">
<?php
// Below code generates the mp4 movie table, if enough files exist
$images = array();
$cycle=6;
$today = date_create();

// take the current day, and substract 6 days past
$lastdate = date_sub($today, date_interval_create_from_date_string($cycle.' days'));

// construct the path for the past 6 days
$wcampath[0] = "wcam/".date_format($lastdate, 'Y/m/d');
$counter = 1;
while($counter<$cycle) {
   date_add($lastdate, date_interval_create_from_date_string('1 days'));
   $wcampath[$counter] = "wcam/".date_format($lastdate, 'Y/m/d');
   $counter++;
}

// check for existing png icon files at those dates
$filecount = 0;
foreach ($wcampath as $path) {
   //echo $path."\n";
   $filename=glob($path."/*.png");
   // check if the file exists, and header is OK
   if(count($filename) == 0) {  continue; }
   if (exif_imagetype($filename[0]) != IMAGETYPE_PNG) { continue; }
   // echo $filename[0]." date: ".filemtime($filename[0])." ".date('Y/m/d H:i:s', filemtime($filename[0]))."\n";
   $images[$filename[0]] = filemtime($filename[0]);
   //echo $images[$filename[0]]."\n";
   $filecount++;
}

// Don't show the movie table unless we have a set of 6
if($filecount == $cycle) {
   echo "For the past six days, all webcam images were combined to one daily MP4 time-lapse movie (35s).\n<p>\n";
   echo "<table class=\"dmovtable\"><tr>\n";

   foreach ($images as $file=>$value) {
      if($filecount > $cycle) break;
      // Check if we have a matching png <--> mp4 file pair
      $pinfo = pathinfo("$file");
      $mp4 = $pinfo['dirname']."/".$pinfo['filename'].".mp4";
      //echo "# ".$mp4."\n";
      if (file_exists($mp4)) {
         echo "<td class=\"dmovcell\"><a href=\"$mp4\">";
         echo "<img class=\"dmovimg\" src=\"$file\" alt=\"$file\"></a>";
         // date("l", provides weekday, M the 3-char month, and j the day.
         echo date("l M j", filemtime($file));
         echo "</td>\n";
      } // end if mp4 file exists
   } // end foreach sorted movie file

   echo "</tr></table>\n";
} // end if movie set is 6
?>
<?php include("./daymimax.htm"); ?>
<p>
<div class="fullgraph"> <img src="images/monthly_temp.png" alt="Weekly Temperature Graph"> </div>
<div class="fullgraph"> <img src="images/monthly_humi.png" alt="Weekly Humidity Graph"> </div>
<div class="fullgraph"> <img src="images/monthly_bmpr.png" alt="Weekly Pressure Graph"> </div>
</div>
<div class="copyright"><a href="javascript:elementHideShow('yearly');">Expand or Hide Midterm Details</a></div>
<h3>Midterm View:</h3>
<hr />
<div class="showext" id="yearly" style="display: none;">
<?php include("./momimax.htm"); ?>
<div class="fullgraph"> <img src="images/yearly_temp.png" alt="Temperature Graph"> </div>
<div class="fullgraph"> <img src="images/yearly_humi.png" alt="Humidity Graph"> </div>
<div class="fullgraph"> <img src="images/yearly_bmpr.png" alt="Pressure Graph"> </div>
</div>
</div>

<div id="sidecontent">
<?php

// get system uptime
function Uptime() {
  $str   = @file_get_contents('/proc/uptime');
  $num   = floatval($str);
  $secs  = $num % 60;
  $num   = (int)($num / 60);
  $mins  = $num % 60;
  $num   = (int)($num / 60);
  $hours = $num % 24;
  $num   = (int)($num / 24);
  $days  = $num;
  $utstr = $days."d:".$hours."h:".$mins."m:".$secs."s";
  return $utstr;
}
$ut = Uptime();

// get system cpu load
$cpu = exec('top -bn 1 | awk \'NR>7{s+=$9} END {print s/4"%"}\'');

// get system ram usage
$mem = exec('free | grep Mem | awk \'{printf("%.0fM of %.0fM\n", $3/1024, $2/1024)}\'');

// get system free disk space
$dfree = exec('df -h | grep \'/dev/root\' | awk {\'print $3 " of " $2\'}');

// get pi-weather config data
ini_set("auto_detect_line_endings", true);
$conf = array();
$fh=fopen($__FILE__."../etc/pi-weather.conf", "r");
while ($line=fgets($fh, 80)) {
  if ((! preg_match('/^#/', $line)) &&    // show only lines w/o #
     (! preg_match('/^$/', $line))) {     // and who are not empty
    $line_a=explode("=", $line);          // explode at the '=' sign
    $conf[$line_a[0]]=$line_a[1];         // assign key/values
  }
}

// get the configured timezone
$newTZ=trim($conf["pi-weather-tzs"]);
$newTZ=str_replace('"', '', $newTZ);

// write station details table to sidebar
echo "<h4>Station Details</h4>\n";
echo "<table class\"station\">\n";
echo "<tr><th>SW Version:</th></tr>\n";
echo "<tr><td>v".$conf["pi-weather-ver"]."</td></tr>\n";
echo "<tr><th>Station ID:</th></tr>\n";
echo "<tr><td>".$conf["pi-weather-sid"]."</td></tr>\n";
echo "<tr><th>Sensor Type:</th></tr>\n";
echo "<tr><td>".$conf["sensor-type"]."</td></tr>\n";
echo "<tr><th>Time Zone:</th></tr>\n";
echo "<tr><td>".$newTZ."</td></tr>\n";
echo "<tr><th>Station Time:</th></tr>\n";
echo "<tr><td>".date("H:i:s")."</td></tr>\n";
echo "<tr><th>GPS Latitude:</th></tr>\n";
echo "<tr><td>".$conf["pi-weather-lat"]."</td></tr>\n";
echo "<tr><th>GPS Longitude:</th></tr>\n";
echo "<tr><td>".$conf["pi-weather-lon"]."</td></tr>\n";
echo "</table>\n";

// write station health table to sidebar
echo "<table class\"station\">\n";
echo "<h4>Station Health</h4>\n";
echo "<tr><th>Station Uptime:</th></tr>\n";
echo "<tr><td>".$ut."</td></tr>\n";
echo "<tr><th>IP Address:</th></tr>\n";
echo "<tr><td>".$_SERVER['SERVER_ADDR']."</td></tr>\n";
echo "<tr><th>CPU Usage:</th></tr>\n";
echo "<tr><td>".$cpu."</td></tr>\n";
echo "<tr><th>RAM Usage:</th></tr>\n";
echo "<tr><td>".$mem."</td></tr>\n";
echo "<tr><th>Disk Usage:</th></tr>\n";
echo "<tr><td>".$dfree."</td></tr>\n";
echo "</table>\n";
?>
    <p style="text-align: middle;">
      <a href="https://raw.githubusercontent.com/fm4dd/pi-weather/master/images/DSC_0033s.jpg"><img src="https://github.com/fm4dd/pi-weather/raw/master/images/DSC_0033s.jpg" height="160px" width="120px"></a>
    <p>
      <a href="https://raw.githubusercontent.com/fm4dd/pi-weather/master/images/DSC_0034s.jpg"><img src="https://github.com/fm4dd/pi-weather/raw/master/images/DSC_0034s.jpg" height="160px" width="120px"></a>
  </div>

  <div id="footer">
    <span class="left">&copy; 2017, FM4DD.com</span>
    <span class="right">Raspberry Pi - running Raspbian</span>
  </div>
</div>
</body>
</html>
