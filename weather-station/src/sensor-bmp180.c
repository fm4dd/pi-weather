/* ------------------------------------------------------------ *
 * file:        sensor-bmp180.c                                 *
 * purpose:     Extract sensor data from Bosch BMP180 modules.  *
 *              Connects through I2C bus and writes barometric  *
 *              air pressure to the global variable for further *
 *              processing. Sensor data is stored in a 176-bit  *
 *              EEPROM, organised in 11x 16-bit words.          *
 *                                                              *
 * Parameters:  i2caddr is a string containing the hex address  *
 *              of the Bosch bmp180 sensor connected to the I2C *
 *              bus. Most modules use address 0x77.             *
 *                                                              *
 *		verbose - enable extra debug output if needed.  *
 *                                                              *
 * Return Code:	Returns 0 on success, and -1 on error.          *
 *                                                              *
 * Requires:	I2C development packages                        *
 *                                                              *
 * author:      06/23/2017 Frank4DD                             *
 *                                                              *
 * compile: gcc sensor-bmp180.c sensor-bmp180.o                 *
 * ------------------------------------------------------------ */
#include <stdio.h>
#include <stdlib.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>

int read_bmp180(char *i2caddr, float *bmpr_ptr, int verbose) {
/* ------------------------------------------------------------ *
 * Get the I2C bus. Raspberry Pi 2 uses i2c-1, RPI 1 used i2c-0
 * ------------------------------------------------------------ */
   int file;
   char *bus = "/dev/i2c-1";
   if((file = open(bus, O_RDWR)) < 0) {
      printf("Error failed to open I2C bus [%s].\n", bus);
      return(-1);
   }
/* ------------------------------------------------------------ *
 * Set I2C device, by default the bmp180 I2C address is 0x76(136)
 * ------------------------------------------------------------ */
   int addr = (int)strtol(i2caddr, NULL, 16);
   if(verbose == 1) printf("Debug: Sensor I2C address: [0x%X]\n", addr);
   ioctl(file, I2C_SLAVE, addr);

/* ------------------------------------------------------------ *
 * Read the sensors chip ID rom register(0xD0), should be 0x55
 * ------------------------------------------------------------ */
   char reg[2] = {0};
   char data[8] = {0};

   reg[0] = 0xD0;
   write(file, reg, 1);

   if(read(file, data, 1) != 1) {
      printf("Error: Input/Output error while reading from bmp180\n");
      return(-1);
   }
   int chip_id = data[0];
   if(verbose == 1) printf("Debug: Sensor chip ID: [%d]\n", chip_id);

/* ------------------------------------------------------------ *
 * Read 22 bytes calibration data calib00-21 from register 0xAA 
 * ------------------------------------------------------------ */
   char calib[22] = {0};

   reg[0] = 0xAA;
   write(file, reg, 1);

   if(read(file, calib, 22) != 22) {
      printf("Error: Cannot read 22 bytes calibration data\n");
      return(-1);
   }

   short ac1, ac2, ac3;
   unsigned short ac4, ac5, ac6;
   short b1, b2, mc, md;

   ac1 = (calib[0] * 256) + calib[1];
   ac2 = (calib[2] * 256) + calib[3];
   ac3 = (calib[4] * 256) + calib[5];
   ac4 = (calib[6] * 256) + calib[7];
   ac5 = (calib[8] * 256) + calib[9];
   ac6 = (calib[10] * 256) + calib[11];
   b1  = (calib[12] * 256) + calib[13];
   b2  = (calib[14] * 256) + calib[15];
   // short mb  = (calib[16] * 256) + calib[17];
   mc  = (calib[18] * 256) + calib[19];
   md  = (calib[20] * 256) + calib[21];

/* ------------------------------------------------------------ *
 * Select control measurement register(0xF4): Sets data output
 * to temp or pressure, and controls oversampling.First we set
 * it for reading temperature by writing 0x2E (00101110) into it:
 * ------------------------------------------------------------ */
   reg[0] = 0xF4;
   reg[1] = 0x2E;
   write(file, reg, 2);
   if(verbose == 1) printf("Debug: write 0x%X to register 0x%X\n", reg[0], reg[1]);

/* ------------------------------------------------------------ *
 * The wait time for before temperature can be read is 4.5 ms
 * ------------------------------------------------------------ */
   usleep(4.5 * 1000); // usleep() uses microsecs, * 1000 = ms

/* ------------------------------------------------------------ *
 * Read the following 2 bytes from read-only data registers:
 * 0xF6 out_msb (temperature msb)
 * 0xF7 out_lsb (temperature lsb)
 * (0xF8 out_xlsb is unused, only usable for pressure readings)
 * ------------------------------------------------------------ */
   reg[0] = 0xF6;
   write(file, reg, 1);
   read(file, data, 2);

/* ------------------------------------------------------------ *
 * Convert the uncompensated temperature data from bytes (16 bit)
 * ------------------------------------------------------------ */
   long ut = (data[0] * 256) + data[1];
   if(verbose == 1) printf("Debug: uncomp temperature value: [%ld]\n", ut);

/* ------------------------------------------------------------ *
 * Temperature compensation calculations
 * ------------------------------------------------------------ */
   long x1 = ((ut - ac6) * ac5) >> 15;
   long x2 = (mc << 11)/(x1 + md);
   long b5 = x1 + x2;
   long ctemp = (b5 + 8)>>4;

/* ------------------------------------------------------------ *
 * ctemp = Temperature in C (and ftemp = Fahrenheit, if needed)
 * ------------------------------------------------------------ */
   if(verbose == 1) printf("Debug: Temperature: [%ld*C]\n", ctemp/10);
   //float fTemp = ctemp * 1.8 + 32;

/* ------------------------------------------------------------ *
 * Select control measurement register(0xF4): Sets data output
 * to temp or pressure, and controls oversampling.
 * Next we set the reading for pressure. Register definitions:
 * osrs = 2 bit, sco = 1 bit, measure mode = 5 bit. 
 * Oversampling setting (OSS) values: 1x=00, 2x=01, 4x=10, 8x=11
 * sco turns 0 when all data registers are filled, otherwise 1
 * Examples: 00110100 = 0x34
 * ------------------------------------------------------------ */
   int oss = 0;    // oss setting: 0=1x, 1=2x, 3=4x, 4=8x
                   // oss is used in compensation calculation below
   reg[0] = 0xF4;
   reg[1] = (0x34 + (oss<<6));
   write(file, reg, 2);
   if(verbose == 1) printf("Debug: write 0x%X to register 0x%X\n", reg[0], reg[1]);

/* ------------------------------------------------------------ *
 * wait time depends on what we read, and on oversampling mode
 * delay is 4.5ms for 1x, 7.5ms for 2x, 13.5ms for 4x, 25.5 for 8
 * ------------------------------------------------------------ */
   int delay = (2 + (3<<oss)) * 1000;
   if(verbose == 1) printf("Debug: pressure read delay: [%d ms]\n", delay);
   usleep(delay);

/* ------------------------------------------------------------ *
 * Read the following 3 bytes from read-only data registers:
 * 0xF6 out_msb (pressure msb)
 * 0xF7 out_lsb (pressure lsb)
 * 0xF8 out_xlsb (pressure xlsb, extends pressure to 19 bit)
 * ------------------------------------------------------------ */
   reg[0] = 0xF6;
   write(file, reg, 1);
   read(file, data, 3);

/* ------------------------------------------------------------ *
 * convert uncompensated pressure data from bytes (19 bit)
 * ------------------------------------------------------------ */
   long up = (((long)(data[0] * 65536)) + ((long)(data[1] * 256)) + (long)data[2]) >> (8-oss); 
   if(verbose == 1) printf("Debug: uncomp pressure value: [%ld]\n", up);

/* ------------------------------------------------------------ *
 * Pressure compensation calculations
 * ------------------------------------------------------------ */
   long x3, b3, b6, bmpr;
   unsigned long b4, b7;

   b6 = b5 - 4000;
   x1 = (b2 * (b6 * b6)>>12)>>11;
   x2 = (ac2 * b6)>>11;
   x3 = x1 + x2;
   b3 = (((((long)ac1 << 2) + x3) << oss) + 2)>>2;
   x1 = (ac3 * b6)>>13;
   x2 = (b1 * ((b6 * b6)>>12))>>16;
   x3 = ((x1 + x2) + 2)>>2;
   b4 = (ac4 * (unsigned long)(x3 + 32768))>>15;
   b7 = ((unsigned long)up - b3) * (50000>>oss);
   bmpr = b7 < 0x80000000 ? (b7 * 2) / b4 : (b7 / b4) * 2;
   x1 = (bmpr>>8) * (bmpr>>8);
   x1 = (x1 * 3038)>>16;
   x2 = (-7357 * bmpr)>>16;
   bmpr = bmpr + ((x1 + x2 + 3791)>>4);

/* ------------------------------------------------------------ *
 * Pressure in Pascal (divide by 100 to get hPa)
 * ------------------------------------------------------------ */
   if(verbose == 1) printf("Debug: Pressure: [%ld Pa]\n", bmpr);
   *bmpr_ptr = (float) bmpr;
   return(0);
}
