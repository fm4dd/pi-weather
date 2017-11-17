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
<h1>Pi-Weather Station <?php echo basename(__DIR__);  ?></h1>
<h2>Raspberry Pi local weather data collection system</h2>

</div>
<div id="vmenu">
  <ul>
    <li><a href="index.php" class="selected" title="Weather Station Data"><span>Station Data</span></a></li>
    <li><a href="showlog.php" title="Weather Station Logs"><span>Station Logs</span></a></li>
    <li><a href="http://weather.fm4dd.com/" title="Weather Station Online"><span>Weather Online</span></a></li>
    <li><a href="http://fm4dd.com/" class="selected" title="FM4DD Site"><span>FM4DD Home</span></a></li>
    <li><a href="https://github.com/fm4dd/pi-weather" title="Weather Station Plans"><span>Github Docs</span></a></li>
  </ul>
</div>

<div id="content">

<?php
include("../common.php");
$conf = array();
$conf = loadConfig(basename(__DIR__));
// set and adjust the timezone
$newTZ=trim($conf["pi-weather-tzs"]);
$newTZ=str_replace('"', '', $newTZ);
date_default_timezone_set($newTZ);
  
if(file_exists("images/raspicam.jpg")) {            // check if file exists
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
}
echo "<hr />\n";
include("./getsensor.htm");
?>

<div class="fullgraph"><img src="images/daily_temp.png" alt="Current Temperature Graph"></div>
<div class="fullgraph"><img src="images/daily_humi.png" alt="Current Humidity Graph"></div>
<div class="fullgraph"><img src="images/daily_bmpr.png" alt="Current Pressure Graph"></div>
<div class="copyright"><a href="javascript:elementHideShow('weekly');">Expand or Hide Shortterm Details</a></div>
<h3>Shortterm View:</h3>
<hr />
<div class="showext" id="weekly" style="display: none;">
<?php
$images = array();
$filecount = 1;
foreach (glob("images/wcam*.png", GLOB_BRACE) as $filename) {
   $images[$filename] = filemtime($filename);
   $filecount++;
}
// Don't show the movies unless we have a set of 6
if($filecount>5) {
   echo "For the past six days, all webcam images were combined to one daily MP4 time-lapse movie (35s).<p>";
   asort($images);
   $newest = array_slice($images, 0, 6);
   $filecount = 1;
   echo "<table class=\"dmovtable\">";
   echo "<tr>";
   foreach ($newest as $file=>$value) {
      if($filecount > 6) break;
      // Check if we have a matching png <--> mp4 file pair
      $pinfo = pathinfo("images/$file");
      $bname = $pinfo['filename'];
      $mp4 = "images/$bname.mp4";
      if (file_exists($mp4)) {
         echo "<td class=\"dmovcell\"><a href=\"$mp4\">";
         echo "<img class=\"dmovimg\" src=\"$file\" alt=\"$file\"></a>";
         // date("l", provides weekday, M the 3-char month, and j the day.
         echo date("l M j", filemtime($file));
         echo "</td>";
         $filecount++;
      } // end if mp4 file exists
   } // end foreach sorted movie file
   echo "</tr></table>";
} // end if movie set is 6

include("./daymimax.htm");
?>
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
<div class="copyright"><a href="javascript:elementHideShow('l_term');">Expand or Hide Longterm Details</a></div>
<h3>Longterm View:</h3>
<hr />
<div class="showext" id="l_term" style="display: none;">
<div class="fullgraph"> <img src="images/twyear_temp.png" alt="Temperature Graph"> </div>
<div class="fullgraph"> <img src="images/twyear_humi.png" alt="Humidity Graph"> </div>
<div class="fullgraph"> <img src="images/twyear_bmpr.png" alt="Pressure Graph"> </div>
</div>
</div>

<div id="sidecontent">
<?php
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
echo "<h4>Station Health</h4>\n";
include("./raspidat.htm");
?>
    <h4>Station Images</h4>
    <a href="https://github.com/fm4dd/pi-weather"><img src="../images/weather-station-v10-10s.png" height="160px" width="120px"></a>
    <a href="https://github.com/fm4dd/pi-weather"><img src="../images/weather-station-v11-02s.png" height="160px" width="120px"></a>
    <a href="https://github.com/fm4dd/pi-weather"><img src="../images/weather-display-v10-05s.png" height="160px" width="120px"></a>
  </div>

  <div id="footer">
    <span class="left">&copy; 2017, FM4DD.com</span>
    <span class="right">Raspberry Pi - running Raspbian</span>
  </div>
</div>
</body>
</html>
