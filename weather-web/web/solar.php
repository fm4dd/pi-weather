<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link rel="stylesheet" type="text/css" href="../style.css" media="screen" />
<link rel="stylesheet" type="text/css" href="solar.css" media="screen" />
<meta name="Title" content="Raspberry Pi Solar Power" />
<meta name="Description" content="Raspberry Pi Solar System" />
<meta name="Keywords" content="Raspberry Pi, Solar, Photovoltaik, Victron" />
<meta name="Classification" content="SOlar Power" />
<style type="text/css">
</style>
<title>Raspberry Pi Solar Power</title>
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
<h2>Solar Power Grid Monitoring</h2>
</div>

<?php include("./vmenu.htm"); ?>

<div id="content">
<?php if(file_exists("./getsolar.htm")) {      // check if file exists
    $tstamp = filemtime("./getsolar.htm");     // get file modification time
    $dt = new DateTime();                      // create new Date object
    $dt->setTimeStamp($tstamp);                // set Date object to tstamp
    $output = $dt->format('l F j Y,  H:i:s');  // format output string
  }
  echo "<h3>Last ve.direct update: $output</h3>\n";
  echo "<hr />\n";
?>

<img class="solarimg" src="images/mppt-75-10.jpg" alt="Victron BlueSolar MPPT 75-10">
<?php include("./getsolar.htm"); ?>

<div class="fullgraph"><img src="images/daily_vbat.png" alt="Battery Voltage"></div>
<div class="fullgraph"><img src="images/daily_vpnl.png" alt="Panel Voltage"></div>
<div class="fullgraph"><img src="images/daily_pbal.png" alt="Load Current"></div>
<div class="copyright"><a href="javascript:elementHideShow('s_term');">Expand or Hide Shortterm Details</a></div>
<h3>Shortterm View:</h3>
<hr />
<div class="showext" id="s_term" style="display: none;">
<?php include("./daypower.htm"); ?>
<p>
<div class="fullgraph"> <img src="images/monthly_vbat.png" alt="Weekly Battery Voltage"> </div>
<div class="fullgraph"> <img src="images/monthly_vpnl.png" alt="Weekly Panel Voltage"> </div>
<div class="fullgraph"> <img src="images/monthly_pbal.png" alt="Weekly Power Balance"> </div>
</div>
<div class="copyright"><a href="javascript:elementHideShow('m_term');">Expand or Hide Midterm Details</a></div>
<h3>Midterm View:</h3>
<hr />
<div class="showext" id="m_term" style="display: none;">
<?php include("./monpower.htm"); ?>
<div class="fullgraph"> <img src="images/yearly_vbat.png" alt="Yearly Battery Voltage"> </div>
<div class="fullgraph"> <img src="images/yearly_vpnl.png" alt="Yearly Panel Voltage"> </div>
<div class="fullgraph"> <img src="images/yearly_pbal.png" alt="Yearly Power Balance"> </div>
</div>

</div>

<div id="sidecontent">
<?php
// write station health table to sidebar
echo "<h4>Station Health</h4>\n";
include("./raspidat.htm");

include("../common.php");
$station=basename(__DIR__);
$conf = array();
$conf = loadConfig($station, "pi-solar.conf");

  echo "<h4>PV System</h4>\n";
  echo "<table class\"station\">\n";
  echo "<tr><th>Charge Controller:</th></tr>\n";
  echo "<tr><td>".$conf["pi-solar-charger"]."</td></tr>\n";
  echo "<tr><th>Controller Rating:</th></tr>\n";
  echo "<tr><td>".$conf["pi-solar-chrate"]."</td></tr>\n";
  echo "<tr><th>PV Panel:</th></tr>\n";
  echo "<tr><td>".$conf["pi-solar-pvtype"]."</td></tr>\n";
  echo "<tr><th>Panel Rating:</th></tr>\n";
  echo "<tr><td>".$conf["pi-solar-pvrate"]."</td></tr>\n";
  echo "<tr><th>Battery Type:</th></tr>\n";
  echo "<tr><td>".$conf["pi-solar-battype"]."</td></tr>\n";
  echo "<tr><th>Battery Rating:</th></tr>\n";
  echo "<tr><td>".$conf["pi-solar-batrate"]."</td></tr>\n";
  echo "</table>\n";
 ?>

    <h4>Solar System Images</h4>
    <a href="https://github.com/fm4dd/pi-victron"><img src="images/solar-system-01.jpg" height="160px" width="120px"></a>
  </div>

  <div id="footer">
    <span class="left">&copy; 2018, FM4DD.com</span>
    <span class="right">Raspberry Pi - running Raspbian</span>
  </div>
</div>
</body>
</html>
