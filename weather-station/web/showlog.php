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

<?php include("./vmenu.htm"); ?>

<div id="content" style="min-height: 630px;">
<?php
  // get CPU temperature
  $cputemp = exec('cat /sys/class/thermal/thermal_zone0/temp |  awk \'{printf("%.2f°C\n", $1/1000)}\'');
  print "<h3>Raspberry Pi CPU temperature: $cputemp</h3>"; ?>
  <hr />
  <div class=\"fullgraph"><img src="images/daily_ctmp.png" alt="Current RPI CPU Temperature"></div>
<?php
  $logpath = "../log";
  $varpath = "../var";

  $files = array(
    "$varpath/sensor.txt",
    "$varpath/backup.txt",
    "$varpath/rrdupdate.log",
    "$varpath/send-data.log",
    "$logpath/outlier.log",
    "$logpath/send-night.log",
    "$logpath/wcam-mkmovie.log",
  );
  ksort($files);

  $default = "../var/send-data.log";
  $finput = (!isset($_GET['p'])) ? "send-data.log" : $_GET['p'];
  foreach($files as $f){
    if(str_ends_with($f, $finput)) { $filename = $f; break; };
    $filename = $default;
  }
  $showlines = (!isset($_GET['lines'])) ? 40 : $_GET['lines'];
  $showlines = (!ctype_digit($showlines)) ? 40 : $showlines;

  if(file_exists($filename)) {
    $tstamp = filemtime($filename);                 // get file modification time
    $ft = new DateTime();                           // create new Date object
    $ft->setTimeStamp($tstamp);                     // set Date object to tstamp
    $output = "File ".basename($filename).", last update ".$ft->format('l F j Y,  H:i:s');
    echo "<h3>$output</h3>\n";
    echo "<hr />\n";

    $alllines = 0;
    if(is_array(file($filename))) { $alllines = count(file($filename)); }
    $output = tail($filename, $showlines);
    if ($output){
      echo "<pre class=\"code\">";
      echo $output;
      echo "</pre>";
      $gotlines = substr_count( $output, "\n" );
      echo "Showing last $gotlines lines from file [".realpath($filename)."] ($alllines total lines).";
    } // endif endif file is_array(), meaning it has lines
  } // endif file_exists
  else  echo "No file found!";
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
      echo "<a href=\"?p=".basename($f)."&lines=".$showlines."\">".basename($f)."</a>";
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
    <a href="https://github.com/fm4dd/pi-weather"><img src="images/weather-station-v10-10s.png" height="160px" width="120px"></a>
    <a href="https://github.com/fm4dd/pi-weather"><img src="images/weather-station-v11-02s.png" height="160px" width="120px"></a>
  </div>

  <div id="footer">
    <span class="left">&copy; 2024, FM4DD.com</span>
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

function str_ends_with($haystack, $needle) {
    $length = strlen($needle);
    if(!$length) return true;
    return substr($haystack, -$length) === $needle;
}
