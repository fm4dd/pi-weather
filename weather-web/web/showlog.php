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
<h1>Pi-Weather Station <?php echo basename(__DIR__); ?></h1>
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

<div id="content" style="min-height: 630px;">

<?php
  include("../common.php");
  $conf = array();
  $conf = loadConfig(basename(__DIR__));
  // set and adjust the timezone
  $newTZ=trim($conf["pi-weather-tzs"]);
  $newTZ=str_replace('"', '', $newTZ);
  date_default_timezone_set($newTZ);

  $datapath = "/srv/app/pi-web01";
  $logpath = $datapath."/chroot/".basename(__DIR__)."/log";
  $varpath = $datapath."/chroot/".basename(__DIR__)."/var";
  $default = $logpath."/rrd.log";

  $filename = (!isset($_GET['p'])) ? $default : urldecode($_GET['p']);
  $showlines = (!isset($_GET['lines'])) ? 40 : $_GET['lines'];

  $files = array( 
    "$varpath/sensor.txt",
    "$varpath/backup.txt",
    "$logpath/outage.log",
    "$logpath/outlier.log",
    "$logpath/rrd.log"
  );
  ksort($files);

  $tstamp = filemtime($filename);                   // get file modification time
  $ft = new DateTime();                             // create new Date object
  $ft->setTimeStamp($tstamp);                       // set Date object to tstamp
  $output = "File ".basename($filename)." content, last update ".$ft->format('l F j Y,  H:i:s');  
  echo "<h3>$output</h3>\n";
  echo "<hr />\n";

  $alllines = 0;
  $alllines = count(file($filename)); 
  $output = tail($filename, $showlines);
  if ($output){ 
    echo "<pre class=\"code\">";
    echo $output;
    echo "</pre>";
  }

  $gotlines = substr_count( $output, "\n" );
  echo "Showing last $gotlines lines from file [".realpath($filename)."] ($alllines total lines).";
?>

</div>

<div id="sidecontent">
  <h4>Station Logs</h4>
  <table>
    <tr><th>File Name</th></tr>
<?php
   if(empty($files)){ return false; }
   foreach($files as $f){
      if(!is_file($f)){ continue; }
      echo "<tr><td>";
      echo "<a href=\"?p=".urlencode($f)."&lines=".$showlines."\">".basename($f)."</a>";
      echo "</td></tr>\n";
   }
?>
  </table>
  <table>
    <tr><th>Display Limit</th></tr>
    <tr><td>
    <form action="" method="get" class="pure-form pure-form-aligned">
    <input type="hidden" name="p" value="<?php echo $filename ?>">
    <select name="lines" onchange="this.form.submit()">
    <option value="10" <?php echo ($showlines=='10') ? 'selected':'' ?>>10</option>
    <option value="40" <?php echo ($showlines=='40') ? 'selected':'' ?>>40</option>
    <option value="80" <?php echo ($showlines=='80') ? 'selected':'' ?>>80</option>
    <option value="240" <?php echo ($showlines=='240') ? 'selected':'' ?>>240</option>
</select>
<label> Log Lines</label>
</form>
    </td></tr>
    </table>
    <a href="https://github.com/fm4dd/pi-weather"><img src="../images/weather-station-v10-10s.png" height="160px" width="120px"></a>
    <a href="https://github.com/fm4dd/pi-weather"><img src="../images/weather-station-v11-02s.png" height="160px" width="120px"></a>
  </div>

  <div id="footer">
    <span class="left">&copy; 2017, FM4DD.com</span>
    <span class="right">Raspberry Pi - running Raspbian</span>
  </div>
</div>
</body>
</html>

<?php function tail($filename, $showlines = 50, $buffer = 4096){
   // Open the file
   if(!is_file($filename)){ return false; }
   $f = fopen($filename, "rb");
   if(!$f){ return false; }
   fseek($f, -1, SEEK_END); // Jump to last character

   // Read and adjust line number if necessary
   // (Otherwise the result would be wrong if file doesn't end with a blank line)
   if(fread($f, 1) != "\n") $showlines -= 1;

   $output = '';
   $chunk = '';

   // While we would like more
   while(ftell($f) > 0 && $showlines >= 0) {
      // Figure out how far back we should jump
      $seek = min(ftell($f), $buffer);
      // Do the jump (backwards, relative to where we are)
      fseek($f, -$seek, SEEK_CUR);
      // Read a chunk and prepend it to our output
      $output = ($chunk = fread($f, $seek)).$output;
      // Jump back to where we started reading
      fseek($f, -mb_strlen($chunk, '8bit'), SEEK_CUR);
      // Decrease our line counter
      $showlines -= substr_count($chunk, "\n");
   }

   // While we have too many lines
   // (Because of buffer size we might have read too many)
   while($showlines++ < 0) {
      // Find first newline and remove all text before that
      $output = substr($output, strpos($output, "\n") + 1);
   }
   // Close file and return
   fclose($f);
   return $output;
}
