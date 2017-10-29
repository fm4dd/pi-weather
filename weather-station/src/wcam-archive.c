/* ------------------------------------------------------------ *
 * file:	wcam-archive.c v1.3                             *
 *                                                              *
 * author:	20170708 Frank4DD [fm4dd.com]                   *
 *                                                              *
 * purpose: 	This program archives the 1-min interval webcam *
 *              images into calendar-based folders. It creates  *
 *              a hardlink to the original image, naming it per *
 *              file creation date and places it into the YYYY/ *
 *              MM/DD directory. It is run from cron every min, *
 *              but only copies files during active time, e.g.  *
 *              between 6:00 and 22:00 o'clock.                 *
 *                                                              *
 *              /etc/crontab entry                              *
 *              * * * * * pi /home/bin/wcam-archive             *
 *                                                              *
 * compile:	gcc wcam-archive.c -o wcam-archive              *
 *                                                              *
 * v1.0 20050307 initial release                                *
 * v1.1 20160904 restrict time with hardcoded start and end hr  *
 * v1.2 20170618 convert hardcoded params to cmdline arguments  *
 * v1.3 20170708 add function for space retention after x days  *
 * ------------------------------------------------------------ */
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

/* ------------------------------------------------------------ *
 * Global variables and defaults                                *
 * ------------------------------------------------------------ */
int verbose = 0;
char imgfile[256];                // the raspicam picture file
char archive[256];                // image archive base folder
int shour = 0;                    // the start time collect pics
int ehour = 23;                   // the end time to collect pics
int keepd = 0;                    // folder retention in days
                                  // if unset, 0 means unlimited

/* ------------------------------------------------------------ *
 * print_usage() prints the programs commandline instructions.  *
 * ------------------------------------------------------------ */
void usage() {
   static char const usage[] = "Usage: wcam-archive -i image -d archive-basedir -s start-hr -e end-hr [-v] | [-h]\n\n\
Command line parameters have the following format:\n\
   -i   latest webcam image file, example: pi-ws01/var/raspicam.jpg\n\
   -d   archive base directory, example: pi-ws01/web/wcam-arch\n\
   -s   start hour to begin creating the archive file, example: 6\n\
   -e   end hour to stop creating the archive file, example: 21\n\
   -r   optional: retention days, delete folders older than today-x, example: 30\n\
        if unset, data grows approx 150MB/day and needs outside housekeeping.\n\
   -v   verbose output flag\n\
   -h   print usage flag\n\n\
Usage example:\n\
./wcam-archive -i /home/pi/pi-ws01/var/raspicam.jpg -d /home/pi/pi-ws01/web/wcam-arch -s 6 -e 21 -v\n\
./wcam-archive -i /home/pi/pi-ws01/var/raspicam.jpg -d /home/pi/pi-ws01/web/wcam-arch -s 6 -e 21 -r 30 -v\n";
   printf(usage);
}

/* ------------------------------------------------------------ *
 * parseargs() checks the commandline arguments with C getopt   *
 * ------------------------------------------------------------ */
void parseargs(int argc, char* argv[]) {
   int arg;
   opterr = 0;

   if(argc == 1) { usage(); exit(-1); }

   while ((arg = (int) getopt (argc, argv, "i:d:s:e:r:vh")) != -1)
      switch (arg) {
         // arg -i + source image file, type: string
         // mandatory, example: pi-ws01/var/raspicam.jpg
         case 'i':
            if(verbose == 1) printf("Debug: arg -i, value %s\n", optarg);
            strncpy(imgfile, optarg, sizeof(imgfile));
            break;

         // arg -d + dst img base dir, type: string
         // mandatory, example: pi-ws01/web/wcam-arch
         case 'd':
            if(verbose == 1) printf("Debug: arg -d, value %s\n", optarg);
            strncpy(archive, optarg, sizeof(archive));
            break;

         // arg -s start time, type: int
         // mandatory, example: 6
         case 's':
            if(verbose == 1) printf("Debug: arg -s, value %s\n", optarg);
            shour = atoi(optarg);
            break;

         // arg -e end time, type: int
         // mandatory, example: 21
         case 'e':
            if(verbose == 1) printf("Debug: arg -e, value %s\n", optarg);
            ehour = atoi(optarg);
            break;

         // arg -r retention in days, type: int
         // optional, example: 30
         case 'r':
            if(verbose == 1) printf("Debug: arg -r, value %s\n", optarg);
            keepd = atoi(optarg);
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
}

/* ------------------------------------------------------------ *
 * filecopy() is the cp equivalent to copy files                *
 * ------------------------------------------------------------ */
int filecopy(char from[],char to[]) {
   FILE* oldfile;
   FILE* newfile;

   if(! (oldfile=fopen(from, "r"))) {
      printf("Error open %s for writing.\n", from);
      return -1;
   }

   umask(022);
   if(! (newfile=fopen(to, "w"))) {
      printf("Error open %s for writing.\n", to);
      return -1;
   }

   int bytes = 0;
   for (;;) {
      int onechar = fgetc(oldfile);
      if (onechar != EOF) fputc(onechar,newfile);
      else break;
      bytes++;
   }
   fclose(oldfile);
   fclose(newfile);
   return bytes;
}

int main(int argc, char *argv[]) {

  time_t wcam_tstamp;
  struct stat wcam_stat;
  struct stat arch_stat;
  char wcam_ydir[256];
  char wcam_mdir[256];
  char wcam_ddir[256];
  char wcam_name[26];
  char newfile[256];
  mode_t mode;
  char year[5];
  char month[3];
  char day[3];
  char hourstr[3];
  int hour;

  /* ------------------------------------------------------------ *
   * Process the cmdline parameters                               *
   * ------------------------------------------------------------ */
  parseargs(argc, argv);

  /* ------------------------------------------------------------ *
   * Check if our dst base directory exists                       *
   * ------------------------------------------------------------ */
  if (stat(archive, &wcam_stat) == -1) {
    if(verbose == 1) printf("Debug: Cannot find archive dir %s\n", archive);
    exit(-1);
  }

  /* ------------------------------------------------------------ *
   * Check if our source img file exists                          *
   * ------------------------------------------------------------ */
  if (stat(imgfile, &wcam_stat) == -1) {
    if(verbose == 1) printf("Debug: Cannot find raspicam file %s\n", imgfile);
    exit(-1);
  }

  /* ------------------------------------------------------------ *
   * Get the image files creation time stamp                      *
   * ------------------------------------------------------------ */
  wcam_tstamp = wcam_stat.st_mtime;

  strftime(hourstr, sizeof(hourstr), "%H", localtime(&wcam_tstamp));
  hour = atoi(hourstr);

  /* ------------------------------------------------------------ *
   * Check if the imgfile time is between start hour and end hour * 
   * and exit if the time is outside operational hours.           *
   * ------------------------------------------------------------ */
  if(hour < shour || hour > (ehour-1)) {
    if(verbose == 1) printf("Debug: File creation hour %d is outside %d..%d\n", hour, shour, ehour);
    exit(0);
  }
  if(verbose == 1) printf("Debug: File creation hour %d is between %d..%d\n", hour, shour, ehour);

  /* ------------------------------------------------------------ *
   * Create archive file name, format <wcam-yyyymmdd_hhmmss.jpg>  *
   * ------------------------------------------------------------ */
  strftime(wcam_name, sizeof(wcam_name), "wcam-%Y%m%d_%H%M%S.jpg", localtime(&wcam_tstamp));
  if(verbose == 1) printf("Debug: Archive file name is [%s]\n", wcam_name);

  /* ------------------------------------------------------------ *
   * Create archive directory structure <base><year><month><day>  *
   * unless it is already there.                                  *
   * ------------------------------------------------------------ */
  mode= 0777 & ~umask(0);

  strftime(year, sizeof(year), "%Y", localtime(&wcam_tstamp));
  strftime(month, sizeof(month), "%m", localtime(&wcam_tstamp));
  strftime(day, sizeof(day), "%d", localtime(&wcam_tstamp));

  snprintf(wcam_ydir, sizeof(wcam_ydir), "%s/%s", archive, year);
  if(stat(wcam_ydir, &arch_stat) == -1) mkdir(wcam_ydir, mode);

  snprintf(wcam_mdir, sizeof(wcam_mdir), "%s/%s/%s", archive, year, month);
  if(stat(wcam_mdir, &arch_stat) == -1) mkdir(wcam_mdir, mode);

  snprintf(wcam_ddir, sizeof(wcam_ddir), "%s/%s/%s/%s", archive, year, month, day);
  if(stat(wcam_ddir, &arch_stat) == -1) mkdir(wcam_ddir, mode);

  /* ------------------------------------------------------------ *
   * copy the image file from temp to archive                     *
   * ------------------------------------------------------------ */
  snprintf(newfile, sizeof(newfile), "%s/%s", wcam_ddir, wcam_name);
  if(verbose == 1) printf("Debug: Archive file name and path is [%s]\n", newfile);

  int bytes=filecopy(imgfile, newfile);
  if(bytes > 0) {
    if(verbose == 1) printf("Debug: Copied [%d] bytes to [%s]\n", bytes, newfile);
  }
  else {
    printf ("Error: Could not copy [%s] to [%s].\n", imgfile, newfile);
  }

  /* ------------------------------------------------------------ *
   * Delete old archive directories (past retention time in days) *
   * for disk space housekeeping (if it exists).                  *
   * ------------------------------------------------------------ */
  if(keepd > 0) {
    time_t reten_tstamp = (time(NULL) - (keepd * 86400));
    strftime(year, sizeof(year), "%Y", localtime(&reten_tstamp));
    strftime(month, sizeof(month), "%m", localtime(&reten_tstamp));
    strftime(day, sizeof(day), "%d", localtime(&reten_tstamp));
    int dircount = 0;
    int filecount = 0;

    if(verbose == 1) printf("Debug: Delete files from [%s-%s-%s]\n", year, month, day);
    snprintf(wcam_ydir, sizeof(wcam_ydir), "%s/%s", archive, year);

    if(stat(wcam_ydir, &arch_stat) == 0) {
      snprintf(wcam_mdir, sizeof(wcam_mdir), "%s/%s/%s", archive, year, month);

      if(stat(wcam_mdir, &arch_stat) == 0) {
        snprintf(wcam_ddir, sizeof(wcam_ddir), "%s/%s/%s/%s", archive, year, month, day);

        if(stat(wcam_ddir, &arch_stat) == 0) {
          if(verbose == 1) printf("Debug: Found expired image folder [%s]\n", wcam_ddir);
          DIR *reten_dir = opendir(wcam_ddir);
          struct dirent *next_file;
          char filepath[256];

          while ((next_file = readdir(reten_dir)) != NULL) {
            sprintf(filepath, "%s/%s", wcam_ddir, next_file->d_name);
            unlink(filepath);
            filecount++;
          }
          closedir(reten_dir);
          if(verbose == 1) printf("Debug: Deleted %d images in folder [%s]\n", filecount, wcam_ddir);
          rmdir(wcam_ddir);
          if(verbose == 1) printf("Debug: Deleted image folder [%s]\n", wcam_ddir);
          dircount++;
        }
        if(strcmp(day, "01") == 0) {
          rmdir(wcam_mdir);
          if(verbose == 1) printf("Debug: Deleted image folder [%s]\n", wcam_mdir);
          dircount++;
        }
      }
      if((strcmp(month, "01") == 0) && (strcmp(day, "01") == 0)) {
          rmdir(wcam_ydir);
          if(verbose == 1) printf("Debug: Deleted image folder [%s]\n", wcam_ydir);
          dircount++;
      }
    }
    if(verbose == 1 && dircount == 0 && filecount == 0) printf("Debug: Nothing to delete.\n");
  }
  exit(0);
}
