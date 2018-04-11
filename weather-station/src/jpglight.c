/* ------------------------------------------------------------ *
 * file:        jpglight.c                                      *
 * purpose:     Takes a single webcam JPEG image, and reads the *
 *              raw pixel data line by line. A brightness value *
 *              is calculated for each line, and for the image  *
 *              itself, turning the webcam into a light sensor. *
 *              Outputs the brightness value between 0 and 1.   *
 *                                                              *
 * return:      Returns 0 if jpeg image can be read. Returns -1 *
 *              for errors.                                     *
 *                                                              *
 * JPEG API:    requires jpeglib.h (see jpeglib-dev package)    *
 *              for rasbian: apt-get libjpeg62-turbo-dev        *
 *                                                              *
 * author:      03/15/2018 Frank4DD                             *
 *                                                              *
 * compile: gcc jpglight.c -o jpglight -ljpeg                   *
 * ------------------------------------------------------------ */
#include <stdio.h>
#include <jpeglib.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <ctype.h>

/* ------------------------------------------------------------ *
 * global variables                                             *
 * ------------------------------------------------------------ */
unsigned char *raw_image = NULL;	// stores the raw, uncompressed image 
int width;				// image width
int height;                             // image height
int bytes_per_pixel;                    // or 1 for GRACYSCALE images
int color_space;       			// or JCS_GRAYSCALE for grayscale images
int verbose = 0;			// debug flag
char filename[256];                     // the source jpeg file
float lightavg = 0;                     // the avg value of light (0 = black)

/* ------------------------------------------------------------ *
 * print_usage() prints the programs commandline instructions.  *
 * ------------------------------------------------------------ */
void usage() {
   static char const usage[] = "Usage: jpglight -s file [-v]\n\
   Command line parameters have the following format:\n\
   -s   mandatory, the jpeg file path\n\
   -h   optional, display this message\n\
   -v   optional, enables debug output\n\
   Usage examples:\n\
./jpglight -s /home/pi/pi-ws01/var/camera.jpg\n";
   printf(usage);
}

/* ------------------------------------------------------------ *
 * parseargs() checks the commandline arguments with C getopt   *
 * ------------------------------------------------------------ */
void parseargs(int argc, char* argv[]) {
  int arg;
  opterr = 0;

  if(argc == 1) { usage(); exit(-1); }

  while ((arg = (int) getopt (argc, argv, "s:vh")) != -1) {
    switch (arg) {
      // arg -s + source jpeg file, type: string
      // mandatory, example: /home/pi/pi-ws01/var/camera.jpg
      case 's':
        if(verbose == 1) printf("Debug: arg -s, value %s\n", optarg);
          strncpy(filename, optarg, sizeof(filename));
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
  if (strlen(filename) < 3) {
    printf("Error: Cannot get valid -s jpeg file argument.\n");
    exit(-1);
  }
}

int main(int argc,char **argv) {
  int ret = 0;
  /* ------------------------------------------------------------ *
   * Process the cmdline parameters                               *
   * ------------------------------------------------------------ */
  parseargs(argc, argv);
  if(verbose == 1) printf("Debug for jpg file:\t%s\n", filename);

  /* ------------------------------------------------------------ *
   * Process the jpeg source file                                 *
   * ------------------------------------------------------------ */
  /* these are libjpeg structures for reading(decompression) */
  struct jpeg_decompress_struct cinfo;
  struct jpeg_error_mgr jerr;
  /* libjpeg data structure, storing one scanline (image row) */
  JSAMPROW row_pointer[1];
 
  /* ------------------------------------------------------------ *
   * Try to open the jpeg image file                              *
   * ------------------------------------------------------------ */
  FILE *infile = fopen(filename, "rb");
  if (!infile) {
    printf("Error opening jpeg file %s\n!", filename);
    return -1;
  }
  /* ------------------------------------------------------------ *
   * Initialize jpeg library, set error handler and decom object. *
   * ------------------------------------------------------------ */
  cinfo.err = jpeg_std_error(&jerr);
  jpeg_create_decompress(&cinfo);

  /* ------------------------------------------------------------ *
   * This makes the library read from infile                      *
   * ------------------------------------------------------------ */
  jpeg_stdio_src(&cinfo, infile);

  /* ------------------------------------------------------------ *
   * Reading the image header (contains image information)        *
   * ------------------------------------------------------------ */
  jpeg_read_header(&cinfo, TRUE);

  /* ------------------------------------------------------------ *
   * Debug: display the JPEG image information                    *
   * ------------------------------------------------------------ */
  if(verbose == 1) {
    printf("Img width x height:\t%d pixels x %d pixels\n", width=cinfo.image_width, height=cinfo.image_height);
    printf("# Colors per pixel:\t%d\n", bytes_per_pixel = cinfo.num_components);
    printf(" Color space count:\t%d (3 = JCS_RGB)\n", cinfo.jpeg_color_space);
  }

  /* ------------------------------------------------------------ *
   * Start image decompression                                    *
   * ------------------------------------------------------------ */
  jpeg_start_decompress(&cinfo);

  /* ------------------------------------------------------------ *
   * Allocate memory to hold the uncompressed image               *
   * ------------------------------------------------------------ */
  size_t img_size = cinfo.output_width * cinfo.output_height * cinfo.num_components;
  raw_image = (unsigned char*)malloc(img_size);
  if(verbose == 1) printf(" Uncompressed size:\t%d bytes\n", img_size);

  /* ------------------------------------------------------------ *
   * Allocate memory to hold the uncompressed image               *
   * ------------------------------------------------------------ */
  size_t row_size = cinfo.output_width * cinfo.num_components;
  row_pointer[0] = (unsigned char *)malloc(row_size);
  if(verbose == 1) printf( "Size of single row:\t%d bytes\n", row_size);

  /* ------------------------------------------------------------ *
   * Variables for in-file positioning                            *
   * ------------------------------------------------------------ */
  unsigned long location = 0; // byte location in jpeg file
  int line = 0;               // row counter variable
  int i = 0;                  // byte location in scanline (row)
  float rowavg = 0;           // the average from all data in one row

  /* ------------------------------------------------------------ *
   * Create a header for verbose pixel output created in the loop *
   * ------------------------------------------------------------ */
  if(verbose == 1) {
    printf("row|pixel-1: R-G-B|pixel-2: R-G-B|pixel-3: R-G-B|pix-638: R-G-B|pix-639: R-G-B|pix-640: R-G-B|lightavg\n");
    printf("------------------------------------------------------------------------------------------------------\n");
  }

  /* ------------------------------------------------------------ *
   * Read one scan line at a time. Pixels are stored by scanlines,*
   * with each scanline running from left to right. The component *
   * values for each pixel are adjacent in the row. For a 24-bit  *
   * RGB image, the row looks like: R,G,B,R,G,B,R,G,B... Each row *
   * is an array of type JSAMPLE - elements are "unsigned char".  *
   * ------------------------------------------------------------ */
  while(cinfo.output_scanline < cinfo.image_height) {
    jpeg_read_scanlines(&cinfo, row_pointer, 1);
    rowavg = 0;

    for(i=0; i<row_size; i++) {
      raw_image[location] = row_pointer[0][i];
      rowavg = rowavg + (float) row_pointer[0][i]/255;

      /* ------------------------------------------------------------ *
       * Below debug output shows sample pixel RGB values for result  *
       * verification. The first and last 3 pixels in a row, for the  *
       * first and last ten rows are getting displayed, together with *
       * the average byte value for each row (0 = black, 1 = white).  *
       * ------------------------------------------------------------ */
      if(verbose == 1) {
        if(line < 10 || line >= cinfo.image_height-10) {
          if(i == 0) printf("%03d|", line);
          if(i < 9 || i >= row_size-9) printf("0x%02x ", row_pointer[0][i]);
          if(i == row_size-1) printf("%.6f\n", rowavg/row_size);
        }
      }
    }

    line++;
    location++;
    lightavg = lightavg + (rowavg/row_size);
  }

  if(verbose == 1) printf("lightavg line summary:\t%.6f (%d lines)\n", lightavg, line);
  lightavg = lightavg / cinfo.image_height;

  /* ------------------------------------------------------------ *
   * Clean up: destroy objects, free pointers, close open files
   * ------------------------------------------------------------ */
  jpeg_finish_decompress(&cinfo);
  jpeg_destroy_decompress(&cinfo);
  free(row_pointer[0]);
  fclose(infile);
  free(raw_image);

  if(verbose == 1) printf("Result average light: %.6f\n", lightavg);
  else printf("%.6f\n", lightavg);
  return 0;
}
