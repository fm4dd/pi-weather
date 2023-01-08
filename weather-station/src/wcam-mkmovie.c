/* ------------------------------------------------------------ *
 * file:	wcam-mkmovie.c v1.4                             *
 *                                                              *
 * author:	20160911 Frank4DD (fm4dd.com)                   *
 *                                                              *
 * purpose:	This program processes archived and timestamped *
 * 		.jpg images of a day by creating frameXXX.jpg   *
 * 		sequence files in a temp folder. Next it calls  *
 * 		ffmpeg for the conversion to a .mp4 movie and   *
 * 		then removes the temporary set of frameXXX.jpg  *
 * 		files. wcam-mkmovie runs from cron once per day *
 *              shortly after midnight. With option -o we get a *
 *              copy to a second movie file e.g. yesterday.mp4  *
 *              that is used to be send to the main web server. *
 *                                                              *
 * cron entry: 	30 0 * * * /home/bin/wcam-mkmovie               *
 *                                                              *
 * compilation: gcc wcam-mkmovie.c -o wcam-mkmovie              *
 *                                                              *
 * Requires: 	libav, imagemagick for mogrify (time imprint)   *
 *                                                              *
 * v1.0 20050307 initial write                                  *
 * v1.1 20160911 adding cmdline args, time imprint              *
 * v1.2 20170708 switching ffmpeg to acconv, changing tmp dir   *
 * v1.3 20170722 adding movie icon creation, 90x68px PNG file   *
 * v1.4 20230103 switching avconf to ffmpeg per RPI OS bullseye *
 * ------------------------------------------------------------ */
#define FFMPEGBIN "/usr/bin/ffmpeg"
#define ZIPBIN    "/usr/bin/zip"
/* ------------------------------------------------------------ *
 * Define the movie parameters: frame rate, codec, quality, etc *
 * ------------------------------------------------------------ */
#define AVOUTARGS "-r 25 -c:v libx264 -s 640x480"
#define AVSILENCE "-nostats -loglevel 0"
/* ------------------------------------------------------------ *
 * Define the icon image parameters: time offset, size, amount  *
 * ------------------------------------------------------------ */
#define AVIMGARGS "-ss 00:00:15 -s 90x68 -vframes 1 -f image2"

#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <ctype.h>
#include <dirent.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <utime.h>
#include <getopt.h>
#include <errno.h>

/* ------------------------------------------------------------ *
 * global variables                                             *
 * ------------------------------------------------------------ */
char archi_home[256];                 // the archived images home directory
char avconv_bin[256] = FFMPEGBIN;     // the path to the ffmpeg program
char avout_args[256] = AVOUTARGS;     // the output arguments for the video
char avimg_args[256] = AVIMGARGS;     // the output arguments for the icon
char avsilencer[256] = AVSILENCE;     // the extra args to prevent ffmpeg output
char target_day[11];                  // the target day to process (yyyy-mm-dd\0)
char movie_file[1024];                // the generated movie file
int verbose = 0;                      // debug output, default "off"
extern char *optarg;
extern int optind, opterr, optopt;

/* ------------------------------------------------------------ *
 * print_usage() prints the programs commandline instructions.  *
 * ------------------------------------------------------------ */
void usage() {
   static char const usage[] = "Usage: wcam-mkmovie [OPTIONS]\n\
Options:\n\
  -a   the path to the archived images (mandatory, e.g. /home/pi/pi-ws03/wcam)\n\
  -f   the path to the ffmpeg program  (optional, default: " FFMPEGBIN ")\n\
  -d   the day to create the movie for (optional, default: yesterday), format yyyy-mm-dd\n\
  -o   the path and name for 2nd movie (optional, e.g. /home/pi/pi-ws03/var/yesterday.mp4)\n\
  -h   print program usage and exit\n\
  -v   enable debug output\n\
\n\
Video Output Args: " AVOUTARGS " \n\
\n\
Usage examples:\n\
./wcam-mkmovie -a /home/pi/pi-ws03/web/wcam \n\
./wcam-mkmovie -d 2017-03-25 -a /home/pi/pi-ws03/web/wcam \n\
./wcam-mkmovie -a /home/pi/pi-ws03/web/wcam -o /home/pi/pi-ws03/var/yesterday.mp4 \n";
   printf(usage);
}

/* ------------------------------------------------------------ *
 * parseargs() checks the commandline arguments with C getopt   *
 * ------------------------------------------------------------ */
void parseargs(int argc, char *argv[]) {
   int arg;
   opterr = 0;

   if(argc == 1) { usage(); exit(-1); }

   while ((arg = (int) getopt (argc, argv, "a:f:d:o:vh")) != -1) {
      switch (arg) {
         // arg -a + wcam archive base dir, type: string
         // optional, example: /home/pi/pi-ws03/wcam
         case 'a':
            if(verbose == 1) printf("Debug: arg -a, value %s\n", optarg);
            strncpy(archi_home, optarg, sizeof(archi_home)-1);
            break;

         // arg -f + ffmpeg binary location, type: string
         // optional, example: /usr/bin/avconv
         case 'f':
            if(verbose == 1) printf("Debug: arg -a, value %s\n", optarg);
            strncpy(avconv_bin, optarg, sizeof(avconv_bin)-1);
            break;

         // arg -d +  day to create the movie for, type: string
         // optional, example: 2017-07-08, format yyyy-mm-dd
         case 'd':
            if(verbose == 1) printf("Debug: arg -d, value %s\n", optarg);
            if(strlen(optarg) == 10) {
               strncpy(target_day, optarg, 10);
            }
            else {
               printf("Error: target_day %s length %zu != 10. Format yyyy-mm-dd required.\n\n", optarg, strlen(optarg));
               usage();
               exit(-1);
            }
            break;

         // arg -o + path and name for 2nd movie, type: string
         // optional, example: /home/pi/pi-ws03/var/yesterday.mp4
         case 'o':
            if(verbose == 1) printf("Debug: arg -o, value %s\n", optarg);
            strncpy(movie_file, optarg, sizeof(movie_file)-1);
            break;

         // arg -v verbose, type: flag, optional
         case 'v':
            verbose = 1; break;

         // arg -h usage, type: flag, optional
         case 'h':
            usage(); exit(0);

         case '?':
            if(isprint (optopt))
               printf("Error: Unknown option `-%c'.\n", optopt);
            else
               printf("Error: Unknown option character `\\x%x'.\n", optopt);
            usage();
            exit(-1);

         default:
            usage();
      }
   }
}

/* ---------------------------------------------------------- *
 * scandir filter returns 1/true if name of file ends in .jpg *
 * ---------------------------------------------------------- */
int filter(const struct dirent *entry) {
   const char *s = entry->d_name;
   if ((strcmp(s, ".") == 0) || (strcmp(s, "..") == 0)) return(0);
   int len = strlen(s) - 4; // index of start of . in .jpg
   if(len >= 0) {
      if (strncmp(s + len, ".jpg", 4) == 0) { return(1); }
   }
   return(0);
}

/* ------------------------------------------------------- *
 * delete_tmp() cleans up the jpg image files copied here  *
 * ------------------------------------------------------- */
int delete_tmp(char *dir) {
   struct dirent *tmpfile_list;
   DIR *tmp_dir;
   char file[258];
   int i=0;

   tmp_dir = opendir(dir);
   for(;;) {
      tmpfile_list = readdir(tmp_dir);
      if(tmpfile_list == NULL) break;
      if(strstr(tmpfile_list->d_name, ".jpg")) {
         snprintf(file, sizeof(file)-1, "%s/%s", dir, tmpfile_list->d_name);
         unlink(file);
         i++;
      }
   }
   free(tmpfile_list);
   return(i);
}

/* ---------------------------------------------------------- *
 * function origin_zip puts the camera jpg image files in a   *
 * .zip file, e.g. # zip -q -m wcam-2016909-jpg *.jpg         *
 * -q = quiet, -m = delete original, -j = strip the path      *
 * ---------------------------------------------------------- */
void origin_zip(char *dir) {
   char cmd[255];
   snprintf(cmd, sizeof(cmd)-1, "%s -q -m -j %s/wcam-%s %s/*.jpg", ZIPBIN, dir, target_day, dir);
   if(verbose == 1) printf("Debug: cmd [%s]\n", cmd);
   system(cmd);
}


/* ------------------------------------------------------------ *
 * filecopy() is the cp equivalent to copy files                *
 * ------------------------------------------------------------ */
int filecopy(char from[],char to[]) {
   FILE* oldfile;
   FILE* newfile;

   if(! (oldfile=fopen(from, "r"))) {
      printf("Error open %s for reading.\n", from);
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
   int ret, bytes;                         // functions return code
   /* ---------------------------------------------------------- *
    * get current time                                           *
    * ---------------------------------------------------------- */
   time_t tstamp = time(NULL);

   /* ---------------------------------------------------------- *
    * process commandline arguments                              *
    * ---------------------------------------------------------- */
   parseargs(argc, argv);
   if(verbose == 1) printf("Debug: wcam-mkmovie started %s", ctime(&tstamp));

  /* ---------------------------------------------------------- *
   * Without a target_day argument, yesterday is the default    *
   * ---------------------------------------------------------- */
   if(strlen(target_day) == 0) {
      tstamp = tstamp - 86400;                // calculate yesterday
      strftime(target_day, 11, "%Y-%m-%d", localtime(&tstamp));
   }

   if(verbose == 1) {
      printf("Debug: target_day [%s]\n", target_day);
      printf("Debug: archi_home [%s]\n", archi_home);
      printf("Debug: avconv_bin [%s]\n", avconv_bin);
      printf("Debug: target_day [%s]\n", target_day);
      printf("Debug: movie_file [%s]\n", movie_file);
   }

   /* ---------------------------------------------------------- *
    * Check if the system binaries ffmpeg and zip exist          *
    * ---------------------------------------------------------- */
   struct stat file_stat;
   if(stat(FFMPEGBIN, &file_stat) == -1) {
      printf("Error: %s does not exist\n", FFMPEGBIN);
      exit(-1);
   }
   if(stat(ZIPBIN, &file_stat) == -1) {
      printf("Error: %s does not exist\n", ZIPBIN);
      exit(-1);
   }

   /* ---------------------------------------------------------- *
    * we expect the following archive directory structure:       *
    * wcam/<year>/<month>/<day> (e.g. created by wcam-archive)   *
    * ---------------------------------------------------------- */
   int i;
   char buf_day[11];                     /* YYYY/MM/MM + \0 = 11 */
   char srcimg_dir[268];

   /* create a tmp day string, replacing '-' with '/' */
   for(i=0; i<=strlen(target_day); i++) {
      if(target_day[i] == '-') buf_day[i] = '/';
      else buf_day[i] = target_day[i];
   }
   buf_day[i+1] = '\0';    // terminate the tmp day string

   snprintf(srcimg_dir, sizeof(srcimg_dir)-1, "%s/%s", archi_home, buf_day);
   if(verbose == 1) printf("Debug: srcimg_dir [%s]\n", srcimg_dir);

   /* ---------------------------------------------------------- *
    * Check if the image source directory exists                 *
    * ---------------------------------------------------------- */
   if(stat(srcimg_dir, &file_stat) == -1) {
      printf("Error: srcimg_dir: %s does not exist\n", srcimg_dir);
      exit(-1);
   }

   /* ---------------------------------------------------------- *
    * Try to access the source images files                      *
    * ---------------------------------------------------------- */
   DIR *src_dir;
   src_dir = opendir(srcimg_dir);
   if (src_dir == NULL) {
      printf("Error: srcimg_dir: %s cannot open\n", srcimg_dir);
      exit(-1);
   }

   /* ---------------------------------------------------------- *
    * Get the list of .jpg files and sort them by time           *
    * ---------------------------------------------------------- */
   int file_counter=0;
   struct dirent **imgfile_list;

   file_counter = scandir(srcimg_dir, &imgfile_list, filter, alphasort);
      if(verbose == 1) printf("Debug: srcimg_dir [%s] - found [%d] files.\n", srcimg_dir, file_counter);
   if(file_counter<=0) {
      printf("Error: srcimg_dir: %s - %d files found\n", srcimg_dir, file_counter);
      exit(-1);
   }

   /* ---------------------------------------------------------- *
    * Create a temporary work directory, check if it can be used *
    * The folder should be under pi-ws01/var, because its tmpfs. *
    * ---------------------------------------------------------- */
   char tmpdir[271];
   struct stat tmp_stat;
   mode_t mode = 0777 & ~umask(0);

   /* Here we track back with ../.. from pi-ws01/web/wcam to var */
   snprintf(tmpdir, sizeof(tmpdir)-1, "%s/../../var/tmp", archi_home);

   if(stat(tmpdir, &tmp_stat) == -1) {
      ret = mkdir(tmpdir, mode);
      if (ret == 0) {
         if(verbose == 1) printf("Debug: Created temporary folder: [%s]\n", tmpdir);
      }
      else {
         printf("Error: Cannot create temporary folder %s: %s\n", tmpdir, strerror(errno));
      }
   }

   src_dir = opendir(tmpdir);
   if (src_dir == NULL) {
     printf("Error: Cannot open temporary folder %s\n", tmpdir);
     exit(-1);
   }

   /* ---------------------------------------------------------- *
    * create image work copies in temporary work directory       *
    * ---------------------------------------------------------- */
   char arch_file[525];  // e.g. /home/pi/pi-ws03/wcam/2016/09/10/wcam-20160910_181907.jpg
   char new_file[294];   // e.g. /home/pi/pi-ws03/var/tmp/frame739.jpg
   struct stat imgstat;  // used to check if the img file size is not zero
   char system_cmd[2048];// shell command string, needs more than 255 for avconv option list

   if(verbose == 1) printf("Debug: Copying [%d] img files -> [%s]\n", file_counter, tmpdir);

   for(i=0; i<file_counter; i++) {
      snprintf(arch_file, sizeof(arch_file)-1, "%s/%s", srcimg_dir, imgfile_list[i]->d_name);

      /* ---------------------------------------------------------- *
       * Check if the img file is empty, if so, we skip processing  *
       * rewind the counter and delete the file from the archive.   *
       * ---------------------------------------------------------- */
      int delcounter = 0;
      stat(arch_file, &imgstat);
      if(imgstat.st_size <= 1) {
         if(verbose == 1) printf("Error: [%s] size is [%lu] ", arch_file, (unsigned long) imgstat.st_size);
         unlink(arch_file);
         delcounter++;
         continue;
      }

      /* ---------------------------------------------------------- *
       * Create the temporary frame image file                      *
       * ---------------------------------------------------------- */
      snprintf(new_file, sizeof(new_file)-1, "%s/frame%03d.jpg", tmpdir, i-delcounter);
      bytes=filecopy(arch_file, new_file);
      if(verbose == 1) printf("%d ", i);

      /* ----------------------------------------------------------- *
       * Add the date and time imprint to frame images, example:     *
       * mogrify -font Liberation-Sans -fill white -undercolor \     *
       * '#00000080' -pointsize 26 -gravity SouthEast -annotate \    *
       * +10+10 "test" frame001.jpg                                  *
       *  ---------------------------------------------------------- */
      char time_hr[3];
      int hlen = strlen(arch_file)-10;
      strncpy(time_hr, arch_file+hlen, 2);
      time_hr[2] = '\0';
      char time_mn[3];
      int mlen = strlen(arch_file)-8;
      strncpy(time_mn, arch_file+mlen, 2);
      time_mn[2] = '\0';
      char imprint[255];
      snprintf(imprint, sizeof(imprint)-1, "Pi-Weather %s Time: %s:%s", target_day, time_hr, time_mn);
      //if(verbose == 1) printf("imprint str: %s\n", imprint);
      snprintf(system_cmd, sizeof(system_cmd)-1, "/usr/bin/mogrify -fill white -undercolor '#00000080' -pointsize 20 -gravity SouthEast -annotate +20+20 '%s' %s", imprint, new_file);
      //if(verbose == 1) printf("system_cmd: %s\n", system_cmd);
      system(system_cmd);
   }
   if(verbose == 1) printf("-> filecopy and mogrify imprint complete\n");
   free(imgfile_list);

   /* ---------------------------------------------------------- *
    * generate video creation time to be embedded as meta data,  *
    * e.g. set the movie creation_date="2017-04-05 22:10:04"     *
    * and set the title="pi-weather 2017-04-04" to image date    *    
    * ---------------------------------------------------------- */
   time_t now = time(NULL);
   char meta_date[36];
   strftime(meta_date, sizeof(meta_date), "creation_time=\"%Y-%m-%d %T\"", localtime(&now));

   char meta_title[128];
   snprintf(meta_title, sizeof(meta_title)-1, "title=\"Pi-Weather %s\"", target_day);

   /* ---------------------------------------------------------- *
    * generate the movie filename for the ffmpeg video package   *
    * ---------------------------------------------------------- */
   char mov_file[268+11];
   int av_ret;

   snprintf(mov_file, sizeof(mov_file)-1, "%s/wcam-%s.mp4", srcimg_dir, target_day);
   if(verbose == 1) printf("Debug: create movie_file 1 [%s]\n", mov_file);

   /* ---------------------------------------------------------- *
    * Create the ffmpeg system command with video arguments      *
    * ---------------------------------------------------------- */
   char cmd_args[1024];
   snprintf(cmd_args, sizeof(cmd_args)-1,
            "%s -i %s/frame%%03d.jpg %s -metadata %s -metadata %s",
            avconv_bin, tmpdir, avout_args, meta_date, meta_title);

   /* ---------------------------------------------------------- *
    * Unless verbose, add "quiet mode" silencer args to ffmpeg   *
    * ---------------------------------------------------------- */
   if(verbose == 1) snprintf(system_cmd, sizeof(system_cmd)-1, "%s %s", cmd_args, mov_file);
   else snprintf(system_cmd, sizeof(system_cmd)-1, "%s %s %s", cmd_args, avsilencer, mov_file);

   /* ---------------------------------------------------------- *
    * execute the movie generation                               *
    * ---------------------------------------------------------- */
   if(verbose == 1) printf("Debug: system_cmd [%s]\n", system_cmd);
   av_ret = system(system_cmd);

   if(av_ret != 0) printf("Error creating movie_file 1 with ffmpeg, return code %d\n", av_ret);
   else if(verbose == 1) printf("Debug: create movie_file 1 completed, return code [%d]\n", av_ret);

   /* ---------------------------------------------------------- *
    * create 2nd movie if -o was given e.g. /tmp/yesterday.mp4   *
    * ---------------------------------------------------------- */
   if(strlen(movie_file) != 0 && av_ret == 0) {
      if(verbose == 1) printf("Debug: create movie_file 2 [%s]\n", movie_file);
     
      // delete any previous file
      struct stat buffer;
      if(stat(movie_file, &buffer) == 0) {
         printf("Deleting previous 2nd movie file %s\n", movie_file);
         unlink(movie_file);
      }

      bytes=filecopy(mov_file, movie_file);
      if(bytes > 0) {
         if(verbose == 1) printf("Debug: Copied [%d] bytes to [%s]\n", bytes, movie_file);
      }
      else {
         printf("Error: Could not copy [%s] to [%s].\n", mov_file, movie_file);
      }
   }

   /* ---------------------------------------------------------- *
    * extract the movie's image png, to be used as a web icon    *
    * ---------------------------------------------------------- */
   char icon_file[286];
   int icon_ret;

   if(av_ret == 0) { 
      snprintf(icon_file, sizeof(icon_file)-1, "%s/wcam-%s.png", srcimg_dir, target_day);
      if(verbose == 1) printf("Debug: create icon_file [%s]\n", icon_file);

      snprintf(cmd_args, sizeof(cmd_args)-1, "%s -i %s %s",
                    avconv_bin, mov_file, avimg_args);

      /* ---------------------------------------------------------- *
       * Unless verbose, add "quiet mode" silencer args to ffmpeg   *
       * ---------------------------------------------------------- */
      if(verbose == 1) snprintf(system_cmd, sizeof(system_cmd)-1, "%s %s", cmd_args, icon_file);
      else snprintf(system_cmd, sizeof(system_cmd)-1, "%s %s %s", cmd_args, avsilencer, icon_file);

      if(verbose == 1) printf("Debug: system_cmd [%s]\n", system_cmd);
      icon_ret = system(system_cmd);

      if(verbose == 1) printf("Debug: system_cmd return code [%d]\n", icon_ret);

      /* -------------------------------------------------------- *
       * backdate icon file to its original content creation date * 
       * touch -t "$(date --date="-1 day" +"%Y%m%d2100")" 1.png   *
       * -------------------------------------------------------- */
      struct stat icon_stat;

      if(stat(icon_file, &icon_stat) == -1) {
         printf("Error: %s does not exist\n", icon_file);
      }
      else {
         char yearstr[5] = { target_day[0], target_day[1], target_day[2], target_day[3], '\0' };
         char monstr[3]  = { target_day[5], target_day[6], '\0' };
         char daystr[3]  = { target_day[8], target_day[9], '\0' };
         if(verbose == 1) printf("Debug: Set icon_file time to [%s][%s][%s]\n", yearstr, monstr, daystr);

         int year = atoi(yearstr);
         int mon  = atoi(monstr);
         int day  = atoi(daystr);

         struct tm tcreate_tm;
         tcreate_tm.tm_year = year-1900;
         tcreate_tm.tm_mon = mon-1;
         tcreate_tm.tm_mday = day;
         tcreate_tm.tm_hour = 21;
         tcreate_tm.tm_min = 0;
         tcreate_tm.tm_sec = 0;

         time_t tcreate = mktime(&tcreate_tm);
         if(tcreate == -1) printf("Error creating tcreate tm struct");

         struct utimbuf new_times;
         new_times.actime = icon_stat.st_atime;   /* keep atime unchanged     */
         new_times.modtime = tcreate;             /* set mtime to create time */
         utime(icon_file, &new_times);            /* apply new time to file   */
      }
   }
   else {
      if(verbose == 1) printf("Debug: No movie file, skip icon_file creation\n");
   }

   /* ---------------------------------------------------------- *
    * clean up the temporary frames                              *
    * ---------------------------------------------------------- */
   int deleted = 0;
   deleted = delete_tmp(tmpdir);
   if(verbose == 1) printf("Debug: Deleted [%d] jpeg files in [%s]\n", deleted, tmpdir);

   /* ---------------------------------------------------------- *
    * If we got a movie, zip up the original jpeg files per day  *
    * ---------------------------------------------------------- */
   if(av_ret == 0) origin_zip(srcimg_dir);

   if(verbose == 1) {
      tstamp = time(NULL);
      printf("Debug: wcam-mkmovie ended %s", ctime(&tstamp));
   }
   exit(0);
}
