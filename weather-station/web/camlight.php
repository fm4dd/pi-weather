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
  // get light value
  $ilum = exec('/home/pi/pi-ws01/bin/jpglight -s /home/pi/pi-ws01/var/raspicam.jpg');
  print "<h3>Raspberry Pi Camera Light: $ilum</h3>"; ?>
  <hr />
  <div class=\"fullgraph"><img src="images/daily_ilum.png" alt="Current Light Value"></div>
  <p></p>
</div>

<div id="sidecontent">
  <h4>Station Light</h4>
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
