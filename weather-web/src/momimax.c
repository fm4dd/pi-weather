/* ------------------------------------------------------------ *
 * file:        momimax.c                                       *
 * purpose:     Extract the daily min/max temperature from the  *
 *              RRD db, and write a html-encoded file with a    *
 *              12-month table, to be included by weather.php   *
 *              using <?php include("./momimax.htm"); ?>.       *
 *                                                              *
 * RRD API:     http://oss.oetiker.ch/rrdtool/doc/librrd.en.html*
 *                                                              *
 * author:      05/03/2017 Frank4DD                             *
 *                                                              *
 * compile: gcc -I/srv/app/rrdtool/include momimax.c -o momimax *
 *              -L/srv/app/rrdtool/lib -lrrd                    *
 * ------------------------------------------------------------ */
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <time.h>
#include <math.h>
#include <rrd.h>

/* ------------------------------------------------------------ *
 * Global variables and defaults                                *
 * ------------------------------------------------------------ */
FILE *html;
int verbose = 0;
int outtype = 0;
char rrdfile[256];
char htmfile[256];
unsigned long ds_cnt = 0;
char **ds_namv;
rrd_value_t *mindata;
rrd_value_t *maxdata;
rrd_value_t *avgdata;
extern char *optarg;
extern int optind, opterr, optopt;
static char mon_name[12][3] = { "Jan", "Feb", "Mar", "Apr",
                                "May", "Jun", "Jul", "Aug",
                                "Sep", "Oct", "Nov", "Dec" };

/* ------------------------------------------------------------ *
 * print_usage() prints the programs commandline instructions.  *
 * ------------------------------------------------------------ */
void usage() {
   static char const usage[] = "Usage: momimax -s [rrd-file] -d|-m [html-output] [-v]\n\
   Command line parameters have the following format:\n\
   -s   RRD file and path, Example: -s /home/pi/pi-ws01/rrd/weather.rrd\n\
   -d   create the 12-day min/max temperature output, and write it into HTML file and path\n\
   -m   create the 12-month min/max temperature output, and write it into HTML file and path\n\
   -y   create the 12-year min/max temperature output, and write it into HTML file and path\n\
   -a   create the 12-year min/max temperature HTML file with the Jan-Dec data for each year\n\
   -h   optional, display this message\n\
   -v   optional, enables debug output\n\
   Usage examples:\n\
./momimax -s /home/pi/pi-ws01/rrd/weather.rrd -a /home/pi/pi-ws01/web/allmimax.htm\n\
./momimax -s /home/pi/pi-ws01/rrd/weather.rrd -y /home/pi/pi-ws01/web/yearmimax.htm\n\
./momimax -s /home/pi/pi-ws01/rrd/weather.rrd -m /home/pi/pi-ws01/web/momimax.htm\n\
./momimax -s /home/pi/pi-ws01/rrd/weather.rrd -d /home/pi/pi-ws01/web/daymimax.htm\n";
   printf(usage);
}

/* ------------------------------------------------------------ *
 * parseargs() checks the commandline arguments with C getopt   *
 * ------------------------------------------------------------ */
void parseargs(int argc, char* argv[]) {
   int arg;
   opterr = 0;

   if(argc == 1) { usage(); exit(-1); }

   while ((arg = (int) getopt (argc, argv, "a:s:d:m:y:vh")) != -1)
      switch (arg) {
         // arg -s + source RRD file, type: string
         // mandatory, example: /opt/raspi/data/weather.rrd
         case 's':
            if(verbose == 1) printf("Debug: arg -s, value %s\n", optarg);
            strncpy(rrdfile, optarg, sizeof(rrdfile)-1);
            break;

         // arg -d + dst HTML file, type: string
         // either -d, -m, -y or -a is mandatory, example: /tmp/t1.htm
         case 'd':
            outtype = 1;
            if(verbose == 1) printf("Debug: arg -d, value %s\n", optarg);
            strncpy(htmfile, optarg, sizeof(htmfile)-1);
            break;

         // arg -m + dst HTML file, type: string
         // either -d, -m, -y or -a is mandatory, example: /tmp/t1.htm
         case 'm':
            outtype = 2;
            if(verbose == 1) printf("Debug: arg -m, value %s\n", optarg);
            strncpy(htmfile, optarg, sizeof(htmfile)-1);
            break;

         // arg -y + dst HTML file, type: string
         // either -d, -m, -y or -a is mandatory, example: /tmp/t1.htm
         case 'y':
            outtype = 3;
            if(verbose == 1) printf("Debug: arg -y, value %s\n", optarg);
            strncpy(htmfile, optarg, sizeof(htmfile)-1);
            break;

         // arg -a + dst HTML file, type: string
         // either -d, -m, -y or -a is mandatory, example: /tmp/t1.htm
         case 'a':
            outtype = 4;
            if(verbose == 1) printf("Debug: arg -a, value %s\n", optarg);
            strncpy(htmfile, optarg, sizeof(htmfile)-1);
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

         default:
            usage();
    }
    if (strlen(rrdfile) < 3) {
       printf("Error: Cannot get valid -s RRD file argument.\n");
       exit(-1);
    }
    if(outtype == 0) {
       printf("Error: Cannot get htm file argument, missing -d|-m?.\n");
       exit(-1);
    }
    if (strlen(htmfile) < 3) {
       printf("Error: Cannot get valid -d htm file argument.\n");
       exit(-1);
    }
}

void all_headhtml(){
   fprintf(html, "<tr><td colspan=13 class=\"monthhead\">12-Year Monthly Maximum Minimum Average Temperatures</td></tr>\n");
   fprintf(html, "<tr>\n");

   /* ------------------------------------------------------------- *
    *  Cycle through the 12 year history columns, oldest first      *
    * ------------------------------------------------------------- */
   int i;
   for(i=0; i<12; i++) {
      /* ------------------------------------------------------------- *
       * Create the header row for individual months                   *
       * ------------------------------------------------------------- */
      if(verbose == 1) printf("Debug: create column head: %.3s\n", mon_name[i]);
      fprintf(html, "   <td class=\"monthcell\">%.3s</td>\n", mon_name[i]);
   }
   /* ------------------------------------------------------------- *
    *  Create the column with the row legend top right after newest *
    * ------------------------------------------------------------- */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Year</td>\n");
   fprintf(html, "</tr>\n");
}

void all_datahtml(int year, time_t ts){
   int h, i, j, k = 0;
   unsigned long step = 86400;

   /* ------------------------------------------------------------- *
    *  Create the year row for min max values to display            *
    * ------------------------------------------------------------- */
   for(h = 0; h<9; h++) {
      int show_year = year-h;
      fprintf(html, "<tr>\n");

      /* ---------------------------------------------------------- *
       *  Create the monthly columms for min max values to display  *
       * ---------------------------------------------------------- */
      for(i=0; i<12; i++) {
         int show_mon = i;

         /* ------------------------------------------------------- *
          * Create the start timestamp for rrdfetch, 1 day of month *
          * ------------------------------------------------------- */
         struct tm start_tm;
         start_tm.tm_year = show_year-1900;
         start_tm.tm_mon  = show_mon;
         start_tm.tm_mday = 1;
         start_tm.tm_hour = 0;
         start_tm.tm_min  = 0;
         start_tm.tm_sec  = 0;
         start_tm.tm_isdst = 0;
   
         time_t tstart = mktime(&start_tm);
         if(tstart == -1) printf("Error");
         if(verbose == 1) printf("Debug: ts=%lld start date=%s", (long long) tstart, ctime(&tstart));

         /* ------------------------------------------------------- *
          * Create the end timestamp for rrdfetch, 1 day next month *
          * ------------------------------------------------------- */
         struct tm end_tm;
         end_tm.tm_year = show_year-1900;
         end_tm.tm_mon  = show_mon+1;
         end_tm.tm_mday = 1;
         end_tm.tm_hour = 0;
         end_tm.tm_min  = 0;
         end_tm.tm_sec  = -1;
         end_tm.tm_isdst = 0;
   
         time_t tend = mktime(&end_tm);
         if(tend == -1) printf("Error creating RRD timerange timestamp tend.");
         if(tstart < ts  && ts < tend) tend = ts; // if we are at the current month, end at now time
         if(verbose == 1) printf("Debug: ts=%lld end date=%s", (long long) tend, ctime(&tend));
   
         /* ---------------------------------------------------------- *
          * In the current year, we cannot see data from the future... *
          * ---------------------------------------------------------- */
         if(tstart > ts) fprintf(html, "   <td class=\"emptycell\">N/A</td>\n");
         else {

            /* ------------------------------------------------------- *
             * rrd_fetch_r() gets RRD values for specific time range.  *
             * 8x function args: 5x input, 3x output, success: ret=0   *
             * (1) const char *filename,                               *
             * (2) const char *consolidation_function,                 *
             * (3) time_t *start,                                      *
             * (4) time_t *end,                                        *
             * (5) unsigned long *step,                                *
             * (6) unsigned long *ds_cnt,                              *
             * (7) char ***ds_namv,                                    *
             * (8) rrd_value_t **data);                                *
             * ------------------------------------------------------- */
            int ret = rrd_fetch_r(rrdfile, "MIN", &tstart, &tend, &step, &ds_cnt, &ds_namv, &mindata);
            if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
            if(verbose == 1) printf("Debug: min rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);
      
            ret = rrd_fetch_r(rrdfile, "MAX", &tstart, &tend, &step, &ds_cnt, &ds_namv, &maxdata);
            if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
            if(verbose == 1) printf("Debug: max rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);
      
            ret = rrd_fetch_r(rrdfile, "AVERAGE", &tstart, &tend, &step, &ds_cnt, &ds_namv, &avgdata);
            if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
            if(verbose == 1) printf("Debug: avg rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

            k=0;
            int days = ((tend - tstart) / 86400)-3;
            if(verbose == 1) printf("Debug: result day count=%d\n", days);
      
            /* --------------------------------------------------------- *
             * Go through the returned dataset, determine min/max values *
             * for temperature. This is the first data src in ds_namv[0].*
             * --------------------------------------------------------- */
            double daymin = DINF;
            double daymax = -1000;
            double dayavg = 0;

            for(j=0; j<(days*ds_cnt); j=j+ds_cnt) {
               k++;
               if(! isnan(mindata[j])) {
                  if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r mindata=[%s:%.2f]\n", k, j, ds_namv[0], mindata[j]);
                  if(daymin > mindata[j]) daymin = mindata[j];
               }
               if(! isnan(maxdata[j])) {
                  if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r maxdata=[%s:%.2f]\n", k, j, ds_namv[0], maxdata[j]);
                  if(daymax < maxdata[j]) daymax = maxdata[j];
               }
               if(! isnan(avgdata[j])) {
                  if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r avgdata=[%s:%.2f]\n", k, j, ds_namv[0], avgdata[j]);
                  dayavg = dayavg + avgdata[j];
               }
            }
            if(daymax != -1000) {
               fprintf(html, "   <td class=\"datacell\">%.1f&deg;C", daymax);
               fprintf(html, " <br> ");
               if(! isinf(daymin)) fprintf(html, "%.1f&deg;C", daymin);
               else  fprintf(html, "N/A");
               fprintf(html, " <br> ");
               if(dayavg != 0) fprintf(html, "%.1f&deg;C</td>\n", dayavg/days);
               else  fprintf(html, "N/A</td>\n");
            }
            else  fprintf(html, "   <td class=\"emptycell\">N/A</td>\n");
         }
      } // end for loop over 12 months of the year
      /* --------------------------------------------------------- *
       * Create the row legend column to the right of newest       *
       * --------------------------------------------------------- */
      fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">%d</td>\n", show_year);
   } // end for loop for year history
}

void year_headhtml(int year){
   fprintf(html, "<tr><td colspan=13 class=\"monthhead\">Yearly Maximum Minimum Average Temperatures</td></tr>\n");
   fprintf(html, "<tr>\n");

   /* ------------------------------------------------------------ *
    *  Cycle through the 12 year history columns, oldest first     *
    * ------------------------------------------------------------ */
   int i;
   for(i = 11; i >= 0; i--) {
      /* --------------------------------------------------------- *
       * Create the header row for individual months               *
       * --------------------------------------------------------- */
      int show_year = year - i;
      if(verbose == 1) printf("Debug: show year=%d\n", show_year);
      fprintf(html, "   <td class=\"monthcell\">%d</td>\n", show_year);
   }
   /* ------------------------------------------------------------ *
    *  Create the column with the row legend, showing the year     *
    * ------------------------------------------------------------ */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Year</td>\n");
   fprintf(html, "</tr>\n");
}

void year_datahtml(int year, time_t ts){
   int i, j, k = 0;
   unsigned long step = 86400;
   /* ------------------------------------------------------------ *
    *  Create the data row for min max values to display           *
    * ------------------------------------------------------------ */
   fprintf(html, "<tr>\n");

   for(i = 11; i >= 0; i--) {
      int show_year = year-i;
      /* ---------------------------------------------------------- *
       * Create the start timestamp for rrd fetch, Jan 1st midnight *
       * ---------------------------------------------------------- */
      struct tm start_tm;
      start_tm.tm_year = show_year-1900;
      start_tm.tm_mon  = 0;
      start_tm.tm_mday = 1;
      start_tm.tm_hour = 0;
      start_tm.tm_min  = 0;
      start_tm.tm_sec  = 0;
      start_tm.tm_isdst = 0;

      time_t tstart = mktime(&start_tm);
      if(tstart == -1) printf("Error");
      if(verbose == 1) printf("Debug: ts=%lld start date=%s", (long long) tstart, ctime(&tstart));

      /* ------------------------------------------------------------- *
       * Create the end timestamp for rrd fetch, Dec 31st 23:59:59     *
       * ------------------------------------------------------------- */
      struct tm end_tm;
      end_tm.tm_year = show_year-1900;
      end_tm.tm_mon  = 11;
      end_tm.tm_mday = 31;
      end_tm.tm_hour = 23;
      end_tm.tm_min  = 59;
      end_tm.tm_sec  = 59;
      end_tm.tm_isdst = 0;

      time_t tend = mktime(&end_tm);
      if(tend == -1) printf("Error creating RRD timerange timestamp tend.");
      if(tend > ts) tend = ts; // if we are at the current date, end at now time
      if(verbose == 1) printf("Debug: ts=%lld end date=%s", (long long) tend, ctime(&tend));

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
      int ret = rrd_fetch_r(rrdfile, "MIN", &tstart, &tend, &step, &ds_cnt, &ds_namv, &mindata);
      if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
      if(verbose == 1) printf("Debug: min rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

      ret = rrd_fetch_r(rrdfile, "MAX", &tstart, &tend, &step, &ds_cnt, &ds_namv, &maxdata);
      if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
      if(verbose == 1) printf("Debug: max rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

      ret = rrd_fetch_r(rrdfile, "AVERAGE", &tstart, &tend, &step, &ds_cnt, &ds_namv, &avgdata);
      if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
      if(verbose == 1) printf("Debug: avg rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

      k=0;
      int days = ((tend - tstart) / 86400)-3;
      if(verbose == 1) printf("Debug: result day count=%d\n", days);

      /* ------------------------------------------------------------- *
       * Go through the returned dataset, and determine min/max values *
       * for temperature, which is the first data source in ds_namv[0].*
       * ------------------------------------------------------------- */
      double daymin = DINF;
      double daymax = -1000;
      double dayavg = 0;

      for(j=0; j<(days*ds_cnt); j=j+ds_cnt) {
         k++;
         if(! isnan(mindata[j])) {
            if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r mindata=[%s:%.2f]\n", k, j, ds_namv[0], mindata[j]);
            if(daymin > mindata[j]) daymin = mindata[j];
         }
         if(! isnan(maxdata[j])) {
            if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r maxdata=[%s:%.2f]\n", k, j, ds_namv[0], maxdata[j]);
            if(daymax < maxdata[j]) daymax = maxdata[j];
         }
         if(! isnan(avgdata[j])) {
            if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r avgdata=[%s:%.2f]\n", k, j, ds_namv[0], avgdata[j]);
            dayavg = dayavg + avgdata[j];
         }
      }
      if(daymax != -1000) {
         fprintf(html, "   <td class=\"datacell\">%.1f&deg;C", daymax);
         fprintf(html, " <br> ");
         if(! isinf(daymin)) fprintf(html, "%.1f&deg;C", daymin);
         else  fprintf(html, "N/A");
         fprintf(html, " <br> ");
         if(dayavg != 0) fprintf(html, "%.1f&deg;C</td>\n", dayavg/days);
         else  fprintf(html, "N/A</td>\n");
      }
      else  fprintf(html, "   <td class=\"emptycell\">N/A</td>\n");
   }
   /* ------------------------------------------------------------- *
    *  Create the column with the row legend to the right of newest *
    * ------------------------------------------------------------- */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Max <br> Min <br> Avg</td>\n");
}

void month_headhtml(int mon, int year){
   fprintf(html, "<tr><td colspan=13 class=\"monthhead\">Monthly Maximum Minimum Average Temperatures</td></tr>\n");
   fprintf(html, "<tr>\n");

   /* ------------------------------------------------------------- *
    *  Cycle through the 12 month history columns, oldest first     *
    * ------------------------------------------------------------- */
   int i;
   for(i = 11; i >= 0; i--) {
      /* ------------------------------------------------------------- *
       * Create the header row for individual months                   *
       * ------------------------------------------------------------- */
      int show_mon = mon-i;
      int show_year = year;
      if (show_mon == 0) { show_mon = 12; show_year = year-1; }
      if (show_mon < 0) { show_mon = show_mon+12; show_year = year-1; }
      if(verbose == 1) printf("Debug: show mon=%d-%d [%.3s]\n", show_year, show_mon, mon_name[show_mon-1]);

      /* ------------------------------------------------------------- *
       * convert year to string, cut first 2 chars for a tight header  *
       * ------------------------------------------------------------- */
      char yearstr[5];
      snprintf(yearstr, sizeof(yearstr), "%d", show_year);
      fprintf(html, "   <td class=\"monthcell\">%.3s %s</td>\n", mon_name[show_mon-1], yearstr+2);
   }
   /* ------------------------------------------------------------- *
    *  Create the column with the row legend top right after newest *
    * ------------------------------------------------------------- */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Mon</td>\n");
   fprintf(html, "</tr>\n");
}

void month_datahtml(int mon, int year, time_t ts){
   int i, j, k = 0;
   unsigned long step = 86400;
   /* ------------------------------------------------------------- *
    *  Create the data row for min max values to display            *
    * ------------------------------------------------------------- */
   fprintf(html, "<tr>\n");
   for(i = 11; i >= 0; i--) {
      int show_mon = mon - i;
      int show_year = year;
      if (show_mon == 0) { show_mon = 12; show_year = year-1; }
      if (show_mon < 0) { show_mon = show_mon+12; show_year = year-1; }
      /* ------------------------------------------------------------- *
       * Create the start timestamp for rrd fetch, 1st day of month.   *
       * ------------------------------------------------------------- */
      struct tm start_tm;
      start_tm.tm_year = show_year-1900;
      start_tm.tm_mon  = show_mon-1;
      start_tm.tm_mday = 1;
      start_tm.tm_hour = 0;
      start_tm.tm_min  = 0;
      start_tm.tm_sec  = 0;
      start_tm.tm_isdst = 0;

      time_t tstart = mktime(&start_tm);
      if(tstart == -1) printf("Error");
      if(verbose == 1) printf("Debug: ts=%lld start date=%s", (long long) tstart, ctime(&tstart));

      /* ------------------------------------------------------------- *
       * Create the end timestamp for rrd fetch, 1st day of next month *
       * ------------------------------------------------------------- */
      struct tm end_tm;
      end_tm.tm_year = show_year-1900;
      end_tm.tm_mon  = show_mon;
      end_tm.tm_mday = 1;
      end_tm.tm_hour = 0;
      end_tm.tm_min  = 0;
      end_tm.tm_sec  = -1;
      end_tm.tm_isdst = 0;

      time_t tend = mktime(&end_tm);
      if(tend == -1) printf("Error creating RRD timerange timestamp tend.");
      if(tend > ts) tend = ts; // if we are at the current month, end at now time
      if(verbose == 1) printf("Debug: ts=%lld end date=%s", (long long) tend, ctime(&tend));

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
      int ret = rrd_fetch_r(rrdfile, "MIN", &tstart, &tend, &step, &ds_cnt, &ds_namv, &mindata);
      if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
      if(verbose == 1) printf("Debug: min rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

      ret = rrd_fetch_r(rrdfile, "MAX", &tstart, &tend, &step, &ds_cnt, &ds_namv, &maxdata);
      if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
      if(verbose == 1) printf("Debug: max rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

      ret = rrd_fetch_r(rrdfile, "AVERAGE", &tstart, &tend, &step, &ds_cnt, &ds_namv, &avgdata);
      if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
      if(verbose == 1) printf("Debug: avg rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

      k=0;
      int days = ((tend - tstart) / 86400)-3;
      if(verbose == 1) printf("Debug: result day count=%d\n", days);

      /* ------------------------------------------------------------- *
       * Go through the returned dataset, and determine min/max values *
       * for temperature, which is the first data source in ds_namv[0].*
       * ------------------------------------------------------------- */
      double daymin = DINF;
      double daymax = -1000;
      double dayavg = 0;

      for(j=0; j<(days*ds_cnt); j=j+ds_cnt) {
         k++;
         if(! isnan(mindata[j])) {
            if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r mindata=[%s:%.2f]\n", k, j, ds_namv[0], mindata[j]);
            if(daymin > mindata[j]) daymin = mindata[j];
         }
         if(! isnan(maxdata[j])) {
            if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r maxdata=[%s:%.2f]\n", k, j, ds_namv[0], maxdata[j]);
            if(daymax < maxdata[j]) daymax = maxdata[j];
         }
         if(! isnan(avgdata[j])) {
            if(verbose == 1) printf("Debug: day [%d] value [%d] rrd_fetch_r avgdata=[%s:%.2f]\n", k, j, ds_namv[0], avgdata[j]);
            dayavg = dayavg + avgdata[j];
         }
      }
      if(daymax != -1000) {
         fprintf(html, "   <td class=\"datacell\">%.1f&deg;C", daymax);
         fprintf(html, " <br> ");
         if(! isinf(daymin)) fprintf(html, "%.1f&deg;C", daymin);
         else  fprintf(html, "N/A");
         fprintf(html, " <br> ");
         if(dayavg != 0) fprintf(html, "%.1f&deg;C</td>\n", dayavg/days);
         else  fprintf(html, "N/A</td>\n");
      }
      else  fprintf(html, "   <td class=\"emptycell\">N/A</td>\n");
   }
   /* ------------------------------------------------------------- *
    *  Create the column with the row legend to the right of newest *
    * ------------------------------------------------------------- */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Max <br> Min <br> Avg</td>\n");
}

void day_headhtml(time_t tsnow){
   /* ------------------------------------------------------------- *
    * Create html table and main header row                         *
    * ------------------------------------------------------------- */
   fprintf(html, "<tr><td colspan=13 class=\"monthhead\">Daily Maximum Minimum Average Temperatures</td></tr>\n");
   fprintf(html, "<tr>\n");

   /* ------------------------------------------------------------- *
    *  Cycle through the 12 days history columns, oldest first      *
    * ------------------------------------------------------------- */
   time_t tshow = tsnow - (86400*12);
   int i;
   for(i = 0; i<12; i++) {
      struct tm show_tm = * localtime(&tshow);   // now
      if(verbose == 1) printf("Debug: show day=%.3s-%d\n", mon_name[show_tm.tm_mon], show_tm.tm_mday);
      fprintf(html, "   <td class=\"monthcell\">%.3s %d</td>\n", mon_name[show_tm.tm_mon], show_tm.tm_mday);
      tshow = tshow + 86400;
   }
   /* ------------------------------------------------------------- *
    *  Create the column with the row legend top right after newest *
    * ------------------------------------------------------------- */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Day</td>\n");
   fprintf(html, "</tr>\n");
   if(verbose == 1) printf("Debug: Finished html date row\n");
}

void day_datahtml(time_t tsnow) {
   unsigned long step = 3600;
   /* ------------------------------------------------------------- *
    *  Create the data row for min max values to display            *
    * ------------------------------------------------------------- */
   time_t tstart = tsnow - (86400 * 12);
   if(verbose == 1) printf("Debug: Create html value row\n");
   if(verbose == 1) printf("Debug: ts=%lld now date=%s", (long long) tsnow, ctime(&tsnow));
   if(verbose == 1) printf("Debug: ts=%lld start date=%s", (long long) tstart, ctime(&tstart));

   struct tm start_tm = * localtime(&tstart);   // now-12 days
   start_tm.tm_hour = 0;
   start_tm.tm_min  = 0;
   start_tm.tm_sec  = 0;
   tstart = mktime(&start_tm);
   if(tstart == -1) printf("Error creating tstart timestamp for day_datahtml");
   if(verbose == 1) printf("Debug: ts=%lld start date=%s", (long long) tstart, ctime(&tstart));

   struct tm end_tm = * localtime(&tsnow);   // now
   end_tm.tm_hour = 0;
   end_tm.tm_min  = 0;
   end_tm.tm_sec  = 0;
   time_t tend = mktime(&end_tm);
   //time_t tend = tsnow;
   if(tend == -1) printf("Error creating tend timestamp for day_datahtml");
   if(verbose == 1) printf("Debug: ts=%lld end date=%s", (long long) tend, ctime(&tend));

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
   int ret = rrd_fetch_r(rrdfile, "MIN", &tstart, &tend, &step, &ds_cnt, &ds_namv, &mindata);
   if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
   if(verbose == 1) printf("Debug: min rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

   ret = rrd_fetch_r(rrdfile, "MAX", &tstart, &tend, &step, &ds_cnt, &ds_namv, &maxdata);
   if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
   if(verbose == 1) printf("Debug: max rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

   ret = rrd_fetch_r(rrdfile, "AVERAGE", &tstart, &tend, &step, &ds_cnt, &ds_namv, &avgdata);
   if (ret != 0) { printf("Error: cannot fetch data from RRD.\n"); exit(-1); }
   if(verbose == 1) printf("Debug: avg rrd_fetch_r return=%d, ds count=%lu\n", ret, ds_cnt);

   fprintf(html, "<tr>\n");

   int i, j=0, k=0;
      double daymin = DINF;
      double daymax = -1000;
      double dayavg = 0;
      /* ------------------------------------------------------------- *
       * Go through the returned dataset, and determine min/max values *
       * The set size is 12 days * 24 hours (60 mins) * 4 data sources *
       * ------------------------------------------------------------- */
   for(i=0; i<(288*ds_cnt); i=i+ds_cnt) {

      if(verbose == 1) printf("Debug: day [%2d] hour [%2d] %s min [%.2f] max [%.2f]\n",
                               k, j, ds_namv[0], mindata[i], maxdata[i]);
      if(! isnan(mindata[i])) {
          if(mindata[i] < daymin) daymin = mindata[i];
      }
      if(! isnan(maxdata[i])) {
          if(maxdata[i] > daymax) daymax = maxdata[i];
      }
      if(! isnan(avgdata[i])) {
          dayavg = dayavg + avgdata[i];
      }
      j++;
      if(j==24) {
         k++; j=0; dayavg=dayavg/24;

         if(verbose == 1) printf("Debug: day [%2d] %s min [%.2f] max [%.2f] avg [%.2f]\n",
                               k-1, ds_namv[0], daymin, daymax, dayavg);
         /* print the max values before processing the next day */
         if(daymax != -1000) {
            fprintf(html, "   <td class=\"datacell\">%.1f&deg;C", daymax);
            fprintf(html, " <br> ");
            if(! isinf(daymin)) fprintf(html, "%.1f&deg;C", daymin);
            fprintf(html, " <br> ");
            if(! isinf(dayavg)) fprintf(html, "%.1f&deg;C</td>\n", dayavg);
         }
         else  fprintf(html, "   <td class=\"emptycell\">N/A</td>\n");

         /* Reset the values before processing the next day */
         daymin = DINF;
         daymax = -1000;
         dayavg = 0;
      }
   }
   /* ------------------------------------------------------------- *
    *  Create the column with the row legend to the right of newest *
    * ------------------------------------------------------------- */
   fprintf(html, "   <td class=\"monthcell\" style=\"width: 1%%; white-space: nowrap;\">Max <br> Min <br> Avg</td>\n");
   if(verbose == 1) printf("Debug: Finished html value row\n");
}

int main(int argc, char *argv[]) {
   /* ------------------------------------------------------------ *
    * Process the cmdline parameters                               *
    * ------------------------------------------------------------ */
   parseargs(argc, argv);
   if(verbose == 1) printf("Debug: RRD file=%s\tHTM file=%s\n", rrdfile, htmfile);

   /* ------------------------------------------------------------ *
    * get current time (now), and time 11 months back (start)      *
    * ------------------------------------------------------------ */
   time_t tsnow = time(NULL);
   struct tm now = * localtime(&tsnow);   // now
   int  this_mon = now.tm_mon + 1;        // tm_mon is 0..11
   int this_year = now.tm_year + 1900;    // tm_year is year since 1900

   if(verbose == 1) printf("Debug: date=%s", ctime(&tsnow));
   if(verbose == 1) printf("Debug: start year-month=%d-%d\n", this_year, this_mon);

   /* ----------------------------------------------------------- *
    *  Open the html file for writing the table data              *
    * ----------------------------------------------------------- */
   if(! (html=fopen(htmfile, "w")))
      printf("Error open %s for writing.\n", htmfile);

   fprintf(html, "<table class=\"dmovtable\">\n");

   /* ------------------------------------------------------------ *
    * If we received -d, create the daily html table data          *
    * ------------------------------------------------------------ */
   if(outtype == 1) {
      day_headhtml(tsnow);
      day_datahtml(tsnow);
   }

   /* ------------------------------------------------------------ *
    * If we received -m, create the monthly html table data        *
    * ------------------------------------------------------------ */
   if(outtype == 2) {
      month_headhtml(this_mon, this_year);
      month_datahtml(this_mon, this_year, tsnow);
   }

   /* ------------------------------------------------------------ *
    * If we received -y, create the yearly html table data         *
    * ------------------------------------------------------------ */
   if(outtype == 3) {
      year_headhtml(this_year);
      year_datahtml(this_year, tsnow);
   }

   /* ------------------------------------------------------------ *
    * If we received -a, create 12-year Jan-Dec html table data    *
    * ------------------------------------------------------------ */
   if(outtype == 4) {
      all_headhtml();
      all_datahtml(this_year, tsnow);
   }

   fprintf(html, "</tr>\n");
   fprintf(html, "</table>\n");
   /* ------------------------------------------------------------ *
    *  Close the html file                                         *
    * ------------------------------------------------------------ */
   fclose(html);
   exit(0);
}
