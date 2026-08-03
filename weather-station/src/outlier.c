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
 * bugfix:      08/02/2026 - see notes below                    *
 *                                                              *
 * FIX NOTES:                                                   *
 *  1) rrd_getvalue() fetched [tslast-100, tslast]. rrdtool     *
 *     always rounds the fetch *end* time UP to the next step   *
 *     boundary. Since tslast (last_update) is rarely exactly   *
 *     on a step boundary, the fetch's last row ended up being  *
 *     the *next, not-yet-written* row - which is always NaN.   *
 *     Since any comparison against NaN in C is false, function *
 *     check_outlier() always returned 0 regardless of newval.  *
 *     Fixed by fetching a wider window and scanning backward   *
 *     for the most recent actual (non-NaN) rows, using the     *
 *     ACTUAL row count/spacing rrd_fetch_r reports back (via   *
 *     the updated tstart/tend/step), instead of assuming a     *
 *     fixed "2 rows returned" layout.                          *
 *  2) rrd_getds() used the deprecated rrd_open()/rrd_init() to *
 *     look up the DS index, and never closed the handle it     *
 *     opened (a file-descriptor leak). rrd_fetch_r() already   *
 *     returns the DS name list and count as part of its normal *
 *     output so that whole detour is removed - the DS index is *
 *     now found directly from the fetch already being done.    *
 *                                                              *
 * compile: gcc -I/srv/app/rrdtool/include outlier.c -o outlier *
 *              -L/srv/app/rrdtool/lib -lrrd                    *
 * ------------------------------------------------------------ */
#define HAVE_STDINT_H

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <rrd.h>
#include <stdint.h>
#include <rrd_client.h>

/* ------------------------------------------------------------ *
 * Global variables and defaults                                *
 * ------------------------------------------------------------ */
#define MAXDSNUM 256              // Max number of data sources in RRD
#define MAXDSLEN 256              // Max length of the data source name
#define CHECKVAL 2                // Num of last values to check
#define FETCH_MARGIN_STEPS 6      // how many steps back to fetch, for safety
int verbose = 0;
char rrdfile[256];                // the rrd file name and path
char dsname[MAXDSLEN];            // the data source name we check
int dsindex = -1;                 // the index number of the selected DS
unsigned long step = 60;          // the step size for the RRD value
unsigned long ds_cnt = 0;         // the data source count
char **ds_namv;
rrd_value_t *lastdata;            // fetched DS values
extern char *optarg;
extern int optind, opterr, optopt;
double newval;                    // Latest measured value
double oldval[CHECKVAL];          // List of old values to check against
double limit;                     // Variance limit to declare error

int isprint(int);

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
         case 's':
            if(verbose == 1) printf("Debug: arg -s, value %s\n", optarg);
            strncpy(rrdfile, optarg, sizeof(rrdfile)-1);
            break;

         case 'd':
            if(verbose == 1) printf("Debug: arg -d, value %s\n", optarg);
            strncpy(dsname, optarg, sizeof(dsname)-1);
            break;

         case 'n':
            if(verbose == 1) printf("Debug: arg -n, value %s\n", optarg);
            newval = strtod(optarg, NULL);
            break;

         case 'p':
            if(verbose == 1) printf("Debug: arg -p, value %s\n", optarg);
            limit = strtod(optarg, NULL);
            break;

         case 'v':
            verbose = 1; break;

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
 * rrd_getvalue() fetches a window ending at the RRD's last       *
 * update and scans backward from the newest row for the most     *
 * recent CHECKVAL actual (non-NaN) samples of the requested DS.  *
 * This also resolves the DS index straight from the fetch's own  *
 * ds_namv, so no separate rrd_open()/rrd_init() call is needed.  *
 * ------------------------------------------------------------- */
void rrd_getvalue(time_t tslast) {
   time_t tstart = tslast - (FETCH_MARGIN_STEPS * step);
   time_t tend   = tslast;
   if(verbose == 1) printf("Debug: requested fetch [%lld .. %lld]\n",
                            (long long)tstart, (long long)tend);

   /* ------------------------------------------------------------- *
    * rrd_fetch_r() gets all RRD values for a specific time range.  *
    * tstart/tend/step are updated in place to the *actual* aligned *
    * range/step rrdtool used - always use those, not the requested *
    * values, to figure out how many rows came back.                *
    * ------------------------------------------------------------- */
   int ret = rrd_fetch_r(rrdfile, "AVERAGE", &tstart, &tend, &step, &ds_cnt, &ds_namv, &lastdata);
   if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
   if(verbose == 1) printf("Debug: rrd_fetch_r return=%d, ds count=%lu, aligned=[%lld..%lld], step=%lu\n",
                            ret, ds_cnt, (long long)tstart, (long long)tend, step);

   if (dsindex == -1) {
      for (unsigned long i = 0; i < ds_cnt; i++) {
         if (verbose == 1) printf("Debug: ds [%lu] = name [%s]\n", i, ds_namv[i]);
         if (strcmp(dsname, ds_namv[i]) == 0) dsindex = (int)i;
      }
      if (dsindex == -1) {
         printf("Error: cannot find DS name %s.\n", dsname);
         exit(-1);
      }
      if (verbose == 1) printf("Debug: ds [%s] = dsindex [%d]\n", dsname, dsindex);
   }

   long rows = (tend - tstart) / (long)step;
   if (rows < 1) { printf("Error: no rows returned from RRD.\n"); exit(-1); }

   /* scan backward from the newest row, keep the last CHECKVAL
    * non-NaN samples we find (skips any not-yet-written trailing row) */
   int found = 0;
   for (long r = rows - 1; r >= 0 && found < CHECKVAL; r--) {
      double v = lastdata[r * ds_cnt + dsindex];
      if (isnan(v)) {
         if (verbose == 1) printf("Debug: row %ld = NaN, skipping\n", r);
         continue;
      }
      /* fill from the back so oldval[CHECKVAL-1] is always the most recent */
      oldval[CHECKVAL - 1 - found] = v;
      if (verbose == 1) printf("Debug: row %ld = %.4f -> oldval[%d]\n",
                                r, v, CHECKVAL - 1 - found);
      found++;
   }

   if (found < CHECKVAL) {
      printf("Error: not enough recent valid data in RRD to check against "
             "(found %d of %d needed - RRD may be too new or have a long "
             "existing outage).\n", found, CHECKVAL);
      exit(-1);
   }
}

/* ------------------------------------------------------------- *
 * check_outlier() compares diff of newval vs oldval to limit    *
 * ------------------------------------------------------------- */
int check_outlier() {
   double diff = 0;
   if(newval > oldval[CHECKVAL-1]) diff = newval-oldval[CHECKVAL-1];
   else diff = oldval[CHECKVAL-1]-newval;
   if(verbose == 1) printf("Debug: SensorReading [%f]\n", newval);
   if(verbose == 1) printf("Debug: Previous Data [%f]\n", oldval[CHECKVAL-1]);
   if(verbose == 1) printf("Debug: Data Variance [%f]\n", diff);

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
   parseargs(argc, argv);

   time_t tsnow = time(NULL);
   time_t tslast;
   tslast = rrd_last_r(rrdfile);

   if(verbose == 1) printf("Debug: outlier prgrun date %s", ctime(&tsnow));
   if(verbose == 1) printf("Debug: last RRD entry date %s", ctime(&tslast));

   rrd_getvalue(tslast);

   ret = check_outlier();
   if(verbose == 1) printf("Debug: Return Value %d\n", ret);
   exit(ret);
}
