<?php
// get pi-weather config data
function loadConfig($station, $conf) {
   $datapath = "/srv/app/pi-web01";          // Set once by setup script
   $confpath = $datapath."/chroot/".$station."/etc/".$conf;

   ini_set("auto_detect_line_endings", true);
   $conf = array();
   $fh = fopen($confpath, "r");
   while ($line=fgets($fh, 80)) {
      if((! preg_match('/^#/', $line)) &&    // show only lines w/o #
         (! preg_match('/^$/', $line))) {    // and who are not empty
         $line_a = explode("=", $line);      // explode at the '=' sign
         $line_a[1]=trim($line_a[1]);        // remove newline char
         $line_a[1]=str_replace('"', '', $line_a[1]); // remove ""
         $conf[$line_a[0]] = $line_a[1];     // assign key/values
      }
   }
   return $conf;
}
function getRRD($station) {
   $datapath = "/srv/app/pi-web01";          // Set once by setup script
   $rrdpath = $datapath."/chroot/".$station."/rrd/".$station.".rrd";
   return $rrdpath;
}
?>
