/* ------------------------------------------------------------ *
 * file:        outlier.c                                       *
 * purpose:     check if the sensor value is widely different   *
 *              from the previously recorded value, suggesting  *
 *              a sensor missreading. This happens on very rare *
 *              occasions and depends on the sensor type.       *
 *              I noticed it 2-3 times a month. Missreads carry *
 *              forward in min/max recordings, beside a unreal  *
 *              spike in the graphs. This program implements a  *
 *              sanity check to see If the latest measurement   *
 *              is off from previous values by a large margin.  *
 *              It requires defining a sensible variance value. *
 *                                                              *
 * return:      Returns 0 if value is within variance, and 1 if *
 *              its outside. The return code is used to re-read *
 *              a sensor value. Another solution is to use a    *
 *              second sensor to get two values for comparison. *
 *                                                              *
 * RRD API:     http://oss.oetiker.ch/rrdtool/doc/librrd.en.html*
 *                                                              *
 * author:      05/30/2017 Frank4DD                             *
 *                                                              *
 * compile: gcc -I/srv/app/rrdtool/include outlier.c -o outlier *
 *              -L/srv/app/rrdtool/lib -lrrd                    *
 * ------------------------------------------------------------ */
#define HAVE_STDINT_H
#define RRD_EXPORT_DEPRECATED  // required to include rrd_format.h

#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <math.h>
#include <rrd.h>
#include <stdint.h>
#include <rrd_client.h>
#include <rrd_format.h>        // required to get rrd_t object

/* ------------------------------------------------------------ *
 * Global variables and defaults                                *
 * ------------------------------------------------------------ */
#define RRD_READONLY    (1<<0)
#define MAXDSNUM 256              // Max number of data sources in RRD
#define MAXDSLEN 256              // Max length of the data source name
#define CHECKVAL 2                // Num of last values to check
int verbose = 0;
char rrdfile[256];                // the rrd file name and path
char dsname[MAXDSLEN];            // the data source name we check
int dsindex = -1;                 // the index number of the selected DS
char ds_list[MAXDSNUM][MAXDSLEN]; // the list of data sources in RRD
unsigned long step = 60;          // the step side for the RRD value
unsigned long ds_cnt = 0;         // the data source ID
char **ds_namv;
rrd_value_t *lastdata;            // the last DS value stored in RRD
extern char *optarg;
extern int optind, opterr, optopt;
double newval;                    // Latest measured value
double oldval[CHECKVAL];          // List of old values to check against
double limit;                     // Variance limit to declare error

int isprint(int);
rrd_file_t *rrd_open(const char *const file_name, rrd_t *rrd, unsigned rdwr);
void rrd_init(rrd_t *rrd);
/* ------------------------------------------------------------ *
 * print_usage() prints the programs commandline instructions.  *
 * ------------------------------------------------------------ */
void usage() {
   static char const usage[] = "Usage: outlier -s [rrd-file] -d [datasource] -n [newvalue] -p [variance] [-v]\n\
   Command line parameters have the following format:\n\
   -s   RRD file and path, Example: -s /opt/raspi/data/am2302.rrd\n\
   -d   RRD data source name\n\
   -n   latest sensor value to check on\n\
   -p   acceptable variance, used as lower and upper boundary\n\
   -h   optional, display this message\n\
   -v   optional, enables debug output\n\
   Usage examples:\n\
./outlier -s /opt/raspi/data/am2302.rrd -d temp -n 9.2 -p 5\n";
   printf(usage);
}

/* ------------------------------------------------------------ *
 * parseargs() checks the commandline arguments with C getopt   *
 * ------------------------------------------------------------ */
void parseargs(int argc, char* argv[]) {
   int arg;
   opterr = 0;

   if(argc == 1) { usage(); exit(-1); }

   while ((arg = (int) getopt (argc, argv, "s:d:n:p:vh")) != -1)
      switch (arg) {
         // arg -s + source RRD file, type: string
         // mandatory, example: /opt/raspi/data/am2302.rrd
         case 's':
            if(verbose == 1) printf("Debug: arg -s, value %s\n", optarg);
            strncpy(rrdfile, optarg, sizeof(rrdfile));
            break;

         // arg -d + RRD data source name, type: string
         // mandatory, example: temp
         case 'd':
            if(verbose == 1) printf("Debug: arg -d, value %s\n", optarg);
            strncpy(dsname, optarg, sizeof(dsname));
            break;

         // arg -n + latest sensor value to check on, type: float
         // mandatory, example: 23.9
         case 'n':
            if(verbose == 1) printf("Debug: arg -n, value %s\n", optarg);
            newval = strtod(optarg, NULL);
            break;

         // arg -p + acceptable variance in percent, type: int
         // mandatory, example: 30
         case 'p':
            if(verbose == 1) printf("Debug: arg -p, value %s\n", optarg);
            limit = strtod(optarg, NULL);
            break;

         // arg -v verbose, type: flag, optional
         case 'v':
            verbose = 1; break;

         // arg -h usage, type: flag, optional
         case 'h':
            usage(); exit(0);

         case '?':
            if (isprint (optopt))
               printf ("Error: Unknown option `-%c'.\n", optopt);
            else
               printf ("Error: Unknown option character `\\x%x'.\n", optopt);

         default:
            usage();
    }
    if (strlen(rrdfile) < 3) {
       printf("Error: Cannot get valid -s RRD file argument.\n");
       exit(-1);
    }
}

/* ------------------------------------------------------------- *
 * rrd_getds() identifies the ds index from the given ds name.   *
 * ------------------------------------------------------------- */
void rrd_getds(const char *filename, const char *ds) {
   rrd_t rrd;
   rrd_init(&rrd);
   rrd_file_t *rrdfile = rrd_open(filename, &rrd, RRD_READONLY);

   if(rrdfile == NULL) {
      printf("Error: cannot open %s.\n", filename);
      exit(-1);
   }

   /* ------------------------------------------------------------- *
    * We could open the RRD file, cycle through the data sources    *
    * ------------------------------------------------------------- */
   if(verbose == 1) printf("Debug: ds count [%ld]\n", rrd.stat_head->ds_cnt);

   int i;
   for(i = 0; i < rrd.stat_head->ds_cnt; i++) {
      if(verbose == 1) printf("Debug: ds [%d] = name [%s]\n", i, rrd.ds_def[i].ds_nam);
      if(i <= MAXDSNUM) strncpy(ds_list[i], rrd.ds_def[i].ds_nam, MAXDSLEN-1);
      int ret = strcmp(ds, rrd.ds_def[i].ds_nam);
      if(ret == 0) dsindex = i;
   }
   if(dsindex == -1) {
      printf("Error: cannot find DS name %s.\n", dsname);
      exit(-1);
   }
   if(verbose == 1) printf("Debug: ds [%s] = dsindex [%d]\n", ds, dsindex);
}

/* ------------------------------------------------------------- *
 * rrd_getvalue() gets the last two values for the ds index      *
 * ------------------------------------------------------------- */
void rrd_getvalue(time_t ts, int ds) {
   time_t tstart = ts-100;
   if(verbose == 1) printf("Debug: start ts [%lld] = start date: %s", (long long) tstart, ctime(&tstart));

   time_t tend = ts;
   if(verbose == 1) printf("Debug: end ts [%lld] = end date: %s", (long long) tend, ctime(&tend));

   /* ------------------------------------------------------------- *
    * rrd_fetch_r() gets all RRD values for a specific time range.  *
    * 8x function args: 5x input, 3x output. Returns 0 for success. *
    * (1) const char *filename,                                     *
    * (2) const char *consolidation_function,                       *
    * (3) time_t *start,                                            *
    * (4) time_t *end,                                              *
    * (5) unsigned long *step,                                      *
    * (6) unsigned long *ds_cnt,                                    *
    * (7) char ***ds_namv,                                          *
    * (8) rrd_value_t **data);                                      *
    * ------------------------------------------------------------- */
   int ret = rrd_fetch_r(rrdfile, "AVERAGE", &tstart, &tend, &step, &ds_cnt, &ds_namv, &lastdata);
   if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
   if(verbose == 1) printf("Debug: min rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

   int i, j = 0;
   for(i=0; i<(2*ds_cnt); i=i+ds_cnt) {
      /* ------------------------------------------------------------- *
       * Go through the returned dataset containing last two values    *
       * ------------------------------------------------------------- */
      if(verbose == 1) printf("Debug: value [%d] rrd_fetch_r data=[%s:%.2f]\n", j, ds_namv[dsindex], lastdata[i+dsindex]);
      oldval[j] = lastdata[i+dsindex];
      j++;
   }
}

/* ------------------------------------------------------------- *
 * check_outlier() compares diff of newval vs oldval to limit    *
 * ------------------------------------------------------------- */
int check_outlier() {
   double diff = 0;
   /* ------------------------------------------------------------- *
    * Calculate difference between newval and oldval                *
    * ------------------------------------------------------------- */
   if(newval > oldval[1]) diff = newval-oldval[1];
   else diff = oldval[1]-newval;
   if(verbose == 1) printf("Debug: SensorReading [%f]\n", newval);
   if(verbose == 1) printf("Debug: Previous Data [%f]\n", oldval[1]);
   if(verbose == 1) printf("Debug: Data Variance [%f]\n", diff);

   /* ------------------------------------------------------------- *
    * Check diff against limit                                      *
    * ------------------------------------------------------------- */
   if(diff > 0 && diff > limit) {
      if(verbose == 1) printf("Debug: Diff [%f] outside Limit [%f]\n", diff, limit);
      return(1);
   }
   else {
      if(verbose == 1) printf("Debug: Diff [%f] within Limit [%f]\n", diff, limit);
      return(0);
   }
}

int main(int argc, char *argv[]) {
   int ret = 0;
   /* ------------------------------------------------------------ *
    * Process the cmdline parameters                               *
    * ------------------------------------------------------------ */
   parseargs(argc, argv);

   /* ------------------------------------------------------------ *
    * get current time (now), and last time of RRD data set        *
    * ------------------------------------------------------------ */
   time_t tsnow = time(NULL);
   time_t tslast;
   tslast = rrd_last_r(rrdfile);

   if(verbose == 1) printf("Debug: outlier prgrun date %s", ctime(&tsnow));
   if(verbose == 1) printf("Debug: last RRD entry date %s", ctime(&tslast));

   rrd_getds(rrdfile, dsname);
   rrd_getvalue(tslast, dsindex);

   ret = check_outlier();
   if(verbose == 1) printf("Debug: Return Value %d\n", ret);
   exit(ret);
}
