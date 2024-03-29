/* ------------------------------------------------------------ *
 * file:        getsensor.c                                     *
 * purpose:     Read sensor data from a supported sensor module *
 *                                                              *
 * params:      -t = sensor type, supported are:                *
 *                   bme280 = Bosch BME 280 I2C sensor          *
 *                   am2302 = AM2302 one-wire sensor + BMP180   *
 *              -a = I2C address for BME280 or BMP180           *
 *              -p = the GPIO pin nunber of AM2302/DHT22 sensor *
 *              -b,c,d = calibration offset for temp, pressure  *
 *                   and humidity                               *
 *              -j = write results into JSON file               *
 *              -o = write results into html file               *
 *                                                              *
 * return:      0 on success, and -1 on errors.                 *
 *                                                              *
 * example:	./getsensor -t bme280 -a 0x76 -o getsensor.htm  *
 * 1493799157 Temp=24.46*C Humidity=35.82% Pressure=1007.84hPa  *
 *                                                              *
 * author:      05/04/2017 Frank4DD                             *
 * ------------------------------------------------------------ */
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <time.h>

#define DHT11 11
#define DHT22 22

/* ------------------------------------------------------------ *
 * Global variables and defaults                                *
 * ------------------------------------------------------------ */
int verbose = 0;
int outflag = 0;
char sentype[256];
char senaddr[256];
char outfile[256];
int sensorpin = 0;
int tempcalib = 0;
int humicalib = 0;
int bmprcalib = 0;
extern char *optarg;
extern int optind, opterr, optopt;

/* ------------------------------------------------------------ *
 * external function prototypes for sensor-type specific code
 * ------------------------------------------------------------ */
int read_bme280(char* addr, float *tptr, float *hptr, float *bptr, int verbose);
int read_am2302(int type, int pin, float *tptr, float *hptr, int verbose);
int read_bmp180(char* addr, float *bptr, int verbose);

/* ------------------------------------------------------------ *
 * print_usage() prints the programs commandline instructions.  *
 * ------------------------------------------------------------ */
void usage() {
   static char const usage[] = "Usage: getsensor -t [type] -a [hex i2c addr] -o [html-output] [-v]\n\
\n\
Command line parameters have the following format:\n\
   -t   sensor module type, Example: bme280\n\
        supported types: bme280, am2302 (in combination with BMP180)\n\
   -a   sensor address on the I2C bus in hex, Example: -a 0x76\n\
   -p   optional, sensor pin for AM2302 sensors, Example: -p 4\n\
   -b   optional, pressure calibration offset, Example: -b 100\n\
   -c   optional, temperature calibration offset, Example: -c -1\n\
   -d   optional, humidity calibration offset, Example: -d -2\n\
   -j   optional, write sensor data to JSON file, Example: -j ./getsensor.json\n\
   -o   optional, write sensor data to HTML file, Example: -o ./getsensor.html\n\
   -h   optional, display this message\n\
   -v   optional, enables debug output\n\
\n\
Usage examples:\n\
./getsensor -t bme280 -a 0x76 -b 50 -c -1 -d -2 -j ./getsensor.json -v\n\
./getsensor -t am2302 -a 0x76 -p 4 -c -1 -o ./getsensor.html -v\n";
   printf(usage);
}

/* ------------------------------------------------------------ *
 * parseargs() checks the commandline arguments with C getopt   *
 * ------------------------------------------------------------ */
void parseargs(int argc, char* argv[]) {
   int arg;
   opterr = 0;

   if(argc == 1) { usage(); exit(-1); }

   while ((arg = (int) getopt (argc, argv, "t:a:p:b:c:d:j:o:vh")) != -1) {
      switch (arg) {
         // arg -t + sensor type, type: string
         // mandatory, example: bme280
         case 't':
            if(verbose == 1) printf("Debug: arg -t, value %s\n", optarg);
            strncpy(sentype, optarg, sizeof(sentype)-1);
            break;

         // arg -a + sensor address, type: string
         // mandatory, example: 0x76
         case 'a':
            if(verbose == 1) printf("Debug: arg -a, value %s\n", optarg);
            strncpy(senaddr, optarg, sizeof(senaddr)-1);
            break;

         // arg -p + sensor pin, type: int
         // optional, example: 7
         case 'p':
            if(verbose == 1) printf("Debug: arg -p, value %s\n", optarg);
            sensorpin = atoi(optarg);
            break;

         // arg -b + barometric pressure calibration, type: int
         // optional, example: +100 (adds 100 Pa to pressure reading)
         case 'b':
            if(verbose == 1) printf("Debug: arg -b, value %s\n", optarg);
            bmprcalib = atoi(optarg);
            break;

         // arg -c + temp calibration, type: int
         // optional, example: -1 (reduces temp -1 degree)
         case 'c':
            if(verbose == 1) printf("Debug: arg -c, value %s\n", optarg);
            tempcalib = atoi(optarg);
            break;

         // arg -d + humidity calibration, type: int
         // optional, example: -2 (reduces humidity -2 %)
         case 'd':
            if(verbose == 1) printf("Debug: arg -d, value %s\n", optarg);
            humicalib = atoi(optarg);
            break;

         // arg -j + dst JSON file, type: string
         // optional, example: /tmp/sensor.json
         case 'j':
            outflag = 2;
            if(verbose == 1) printf("Debug: arg -j, value %s\n", optarg);
            strncpy(outfile, optarg, sizeof(outfile)-1);
            break;

         // arg -o + dst HTML file, type: string
         // optional, example: /tmp/sensor.htm
         case 'o':
            outflag = 1;
            if(verbose == 1) printf("Debug: arg -o, value %s\n", optarg);
            strncpy(outfile, optarg, sizeof(outfile)-1);
            break;

         // arg -v verbose, type: flag, optional
         case 'v':
            verbose = 1; break;

         // arg -h usage, type: flag, optional
         case 'h':
            usage(); exit(0);

         case '?':
            if(isprint (optopt))
               printf ("Error: Unknown option `-%c'.\n", optopt);
            else
               printf ("Error: Unknown option character `\\x%x'.\n", optopt);
            usage();
            exit(-1);

         default:
            usage();
      }
   }
   if (strlen(sentype) != 6) {
      printf("Error: Cannot get valid -t sensor type argument.\n");
      exit(-1);
   }
   if (strlen(senaddr) != 4) {
      printf("Error: Cannot get valid -a sensor address argument.\n");
      exit(-1);
   }
}

int main(int argc, char *argv[]) {
   float temp;
   float humi;
   float bmpr;
   /* ------------------------------------------------------------ *
    * Process the cmdline parameters                               *
    * ------------------------------------------------------------ */
   parseargs(argc, argv);

   /* ------------------------------------------------------------ *
    * get current time (now), write program start if verbose       *
    * ------------------------------------------------------------ */
   time_t tsnow = time(NULL);
   if(verbose == 1) printf("Debug: ts=[%lld] date=%s", (long long) tsnow, ctime(&tsnow));

   /* ----------------------------------------------------------- *
    *  Read the bme280 sensor                                     *
    * ----------------------------------------------------------- */
   int res = -1;
   if(strcmp(sentype, "bme280") == 0) {
      res = read_bme280(senaddr, &temp, &humi, &bmpr, verbose);
      if(res != 0) {
         printf("Error: Cannot read sensor %s, return code %d.\n", sentype, res);
         exit(-1);
      }
   }

   /* ----------------------------------------------------------- *
    *  Read the am2302/dht22 sensor, combined with bmp180         *
    * ----------------------------------------------------------- */
   if(strcmp(sentype, "am2302") == 0) {
      if(sensorpin == 0) {
         printf("Error: Cannot get valid -p sensor pin address argument.\n");
	 exit(-1);
      }

      /* -------------------------------------------------------- *
       * DHT sensor cannot be read frequently, only to be queried *
       * once in 2sec. If we hit the read error, retry 15x times  *
       * with 2sec wait in between before giving up after 30secs. *
       * -------------------------------------------------------- */
      int retry = 0;
      int retrymax = 15;
      while(retry < retrymax) {
        res = read_am2302(DHT22, sensorpin, &temp, &humi, verbose);
        if(res == 0) break;
        sleep(2);
        retry++;
      }

      if(res != 0) {
         printf("Error: Cannot read sensor %s after %d attempts, return code %d.\n", sentype, retrymax, res);
         exit(-1);
      }
      else {
        if(verbose == 1) printf("Debug: Sensor read success after %d retries.\n", retry);
      }

      res = read_bmp180(senaddr, &bmpr, verbose);
      if(res != 0) {
         printf("Error: Cannot read sensor bmp180, return code %d.\n", res);
         exit(-1);
      }
   } /* End reading am2302/dht22+bmp180 sensors */

   /* -------------------------------------------------------- *
    *  Add calibration values, adjust data before final output *
    * -------------------------------------------------------- */
   if(verbose == 1) printf("Debug: sensor read temp=[%.2f] humi=[%.2f] bmpr=[%.2f]\n", temp, humi, bmpr);
   if(tempcalib != 0) {
      temp = temp + tempcalib;
      if(verbose == 1) printf("Debug: Adjust temperature with calibration offset [%d]\n", tempcalib);
   }

   if(bmprcalib != 0) {
      bmpr = bmpr + bmprcalib;
      if(verbose == 1) printf("Debug: Adjust pressure with calibration offset [%d]\n", bmprcalib);
   }

   if(humicalib != 0) {
      humi = humi + humicalib;
      if(verbose == 1) printf("Debug: Adjust humidity with calibration offset [%d]\n", humicalib);
   }

   if(outflag == 1) {
      /* -------------------------------------------------------- *
       *  Open the html file for writing the table data           *
       * -------------------------------------------------------- */
      FILE *html;
      if(! (html=fopen(outfile, "w"))) {
         printf("Error open %s for writing.\n", outfile);
         exit(-1);
      }
      fprintf(html, "<table><tr>\n");
      fprintf(html, "<td class=\"sensordata\">Air Temperature:<span class=\"sensorvalue\">%.2f&deg;C</span></td>\n", temp);
      fprintf(html, "<td class=\"sensorspace\"></td>\n");
      fprintf(html, "<td class=\"sensordata\">Relative Humidity:<span class=\"sensorvalue\">%.2f&thinsp;%%</span></td>\n", humi);
      fprintf(html, "<td class=\"sensorspace\"></td>\n");
      fprintf(html, "<td class=\"sensordata\">Barometric Pressure:<span class=\"sensorvalue\">%.2f&thinsp;hPa</span></td>\n", bmpr/100);
      fprintf(html, "</tr></table>\n");
      fclose(html);
   }

   if(outflag == 2) {
      /* -------------------------------------------------------- *
       *  Open the JSON file for writing: { "time": 1649061666,   *
       *  "temp": 10.94, "humi": 85.91, "pres": 101957.88 }       *
       * -------------------------------------------------------- */
      FILE *json;
      if(! (json=fopen(outfile, "w"))) {
         printf("Error open %s for writing.\n", outfile);
         exit(-1);
      }
      fprintf(json, "{ \"time\": %lld, \"temp\": %.2f, \"humi\": %.2f, \"pres\": %.2f }", (long long) tsnow, temp, humi, bmpr);
      fclose(json);
   }

   /* ----------------------------------------------------------- *
    * print the formatted output string to stdout (Example below) *              
    * 1498385783 Temp=27.34*C Humidity=55.82% Pressure=99702.00Pa *
    * ----------------------------------------------------------- */
   printf("%lld Temp=%.2f*C Humidity=%.2f%% Pressure=%.2fPa\n",
         (long long) tsnow, temp, humi, bmpr);

   exit(0);
}
