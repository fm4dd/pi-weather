/* ------------------------------------------------------------ *
 * file:        sensor-bme280.c                                 *
 * purpose:     Extract sensor data from Bosch BME280 modules.  *
 *              Connects through I2C bus and writes temperature *
 *              relative humidity and barometric air pressure   *
 *              into global variables for processing.           *
 *                                                              *
 * Parameters:  i2caddr is a string containing the hex address  *
 *              of the Bosch BME280 sensor connected to the I2C *
 *              bus. Akizuki Denshi modules use 0x76 and 0x77.  *
 *                                                              *
 *		verbose - enable extra debug output if needed.  *
 *                                                              *
 * Return Code:	Returns 0 on success, and -1 on error.          *
 *                                                              *
 * Requires:	I2C development packages                        *
 *                                                              *
 * author:      06/23/2017 Frank4DD                             *
 *                                                              *
 * compile: gcc sensor-bme280.c sensor-bme280.o                 *
 * ------------------------------------------------------------ */
#include <stdio.h>
#include <stdlib.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>

int read_bme280(char *i2caddr, float *temp_ptr, float *humi_ptr,
                                  float *bmpr_ptr, int verbose) {
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
 * Set I2C device, by default the BME280 I2C address is 0x76(136)
 * ------------------------------------------------------------ */
   int addr = (int)strtol(i2caddr, NULL, 16);
   if(verbose == 1) printf("Debug: Sensor I2C address: [0x%X]\n", addr);

   ioctl(file, I2C_SLAVE, addr);

/* ------------------------------------------------------------ *
 * Read 1 byte, the sensors chip ID rom register(0xD0)
 * ------------------------------------------------------------ */
   char reg[1] = {0xD0};
   write(file, reg, 1);
   char data[8] = {0};
   if(read(file, data, 1) != 1) {
      printf("Error: Input/Output error while reading from bme280\n");
      return(-1);
   }
   int chip_id = data[0];
   if(verbose == 1) printf("Debug: Sensor chip ID: [%d]\n", chip_id);

/* ------------------------------------------------------------ *
 * Read 24 bytes calib00-23 calibration data from register(0x88)
 * ------------------------------------------------------------ */
   reg[0] = 0x88;
   write(file, reg, 1);

   char b1[24] = {0};
   if(read(file, b1, 24) != 24) {
      printf("Error: Cannot read 24 bytes calibration data\n");
      return(-1);
   }

/* ------------------------------------------------------------ *
 * Convert the data: temp coefficents
 * ------------------------------------------------------------ */
   int dig_T1 = (b1[0] + b1[1] * 256);
   int dig_T2 = (b1[2] + b1[3] * 256);
   if(dig_T2 > 32767) dig_T2 -= 65536;
   int dig_T3 = (b1[4] + b1[5] * 256);
   if(dig_T3 > 32767) dig_T3 -= 65536;

   // pressure coefficents
   int dig_P1 = (b1[6] + b1[7] * 256);
   int dig_P2 = (b1[8] + b1[9] * 256);
   if(dig_P2 > 32767) dig_P2 -= 65536;
   int dig_P3 = (b1[10] + b1[11] * 256);
   if(dig_P3 > 32767) dig_P3 -= 65536;
   int dig_P4 = (b1[12] + b1[13] * 256);
   if(dig_P4 > 32767) dig_P4 -= 65536;
   int dig_P5 = (b1[14] + b1[15] * 256);
   if(dig_P5 > 32767) dig_P5 -= 65536;
   int dig_P6 = (b1[16] + b1[17] * 256);
   if(dig_P6 > 32767) dig_P6 -= 65536;
   int dig_P7 = (b1[18] + b1[19] * 256);
   if(dig_P7 > 32767) dig_P7 -= 65536;
   int dig_P8 = (b1[20] + b1[21] * 256);
   if(dig_P8 > 32767) dig_P8 -= 65536;
   int dig_P9 = (b1[22] + b1[23] * 256);
   if(dig_P9 > 32767) dig_P9 -= 65536;

/* ------------------------------------------------------------ *
 * Read 1 byte of data from calibration register dig_H1 (0xA1)
 * ------------------------------------------------------------ */
   reg[0] = 0xA1;
   write(file, reg, 1);
   memset(data, 0, sizeof(data));
   read(file, data, 1);
   int dig_H1 = data[0];

/* ------------------------------------------------------------ *
 * Read 7 bytes of data from register(0xE1) calib26-41
 * ------------------------------------------------------------ */
   reg[0] = 0xE1;
   write(file, reg, 1);
   read(file, b1, 7);

/* ------------------------------------------------------------ *
 * Convert the data: humidity coefficents
 * ------------------------------------------------------------ */
   int dig_H2 = (b1[0] + b1[1] * 256);
   if(dig_H2 > 32767) dig_H2 -= 65536;
   int dig_H3 = b1[2] & 0xFF ;
   int dig_H4 = (b1[3] * 16 + (b1[4] & 0xF));
   if(dig_H4 > 32767) dig_H4 -= 65536;
   int dig_H5 = (b1[4] / 16) + (b1[5] * 16);
   if(dig_H5 > 32767) dig_H5 -= 65536;
   int dig_H6 = b1[6];
   if(dig_H6 > 127) dig_H6 -= 256;

/* ------------------------------------------------------------ *
 * Select control humidity register(0xF2). This register uses  
 * only 3-bit, remaining 5 are reserved (don't change). Example:
 * Humidity OS=1x: 0x01, OS=4x: 0x03
 * ------------------------------------------------------------ */
   char config[2] = {0};
   config[0] = 0xF2;
   config[1] = 0x01;
   write(file, config, 2);

/* ------------------------------------------------------------ *
 * Select control measurement register(0xF4): Settting mode and
 * oversampling for temp and pressure. Register definition:
 * osrs_t = 3 bit, osrs_h = 3 bit, mode = 2 bit. Examples:
 * OS=1x, mode=normal: osrs_t=001, osrs_h=001, mode=11 = 0x27
 * OS=1x, mode=forced: osrs_t=001, osrs_h=001, mode=01 = 0x25
 * OS=4x, mode=normal: osrs_t=011, osrs_h=011, mode=11 = 0x6F
 * OS=4x, mode=forced: osrs_t=011, osrs_h=011, mode=01 = 0x6D
 * ------------------------------------------------------------ */
   config[0] = 0xF4;
   config[1] = 0x6D;
   write(file, config, 2);

/* ------------------------------------------------------------ *
 * Select config register(0xF5), sets rate, filter and interface
 * options. bit0=1: enable 3-wire SPI, bit2-4=IIR filter time,
 * and bit5-7=stand_by time in normal mode: 000=0.5ms (lowest),
 * 101=1000ms (1 second, highest). Examples:
 * stdby-time 1000: 101 IIR-filter off: 000 3-wire SPI: 0 = 0xA0
 * stdby-time 0.5: 000, IIR-filter off: 000 3-wire SPI: 0 = 0x00
 * When using the IIR filter, normal mode is recommended.
 * ------------------------------------------------------------ */
   config[0] = 0xF5;
   config[1] = 0xA0;
   write(file, config, 2);

   usleep(4.5 * 1000);

/* ------------------------------------------------------------ *
 * Read the following 8 bytes from read-only data registers:
 * 0xF7 press_msb (pressure msb)
 * 0xF8 press_lsb (pressure lsb)
 * 0xF9 press_xlsb (pressure xlsb, extend result to 20bit)
 * 0xFA temp_msb (temperature msb)
 * 0xFB temp_lsb (temperature lsb)
 * 0xFC temp_xlsb (temperature xlsb, extend result to 20bit)
 * 0xFD hum_msb (humidity msb)
 * 0xFB hum_lsb (humidity lsb)
 * ------------------------------------------------------------ */
   reg[0] = 0xF7;
   write(file, reg, 1);
   read(file, data, 8);

/* ------------------------------------------------------------ *
 * Convert pressure and temperature data
 * ------------------------------------------------------------ */
   long adc_p = ((long)(data[0] * 65536 + ((long)(data[1] * 256) + (long)(data[2] & 0xF0)))) / 16;
   long adc_t = ((long)(data[3] * 65536 + ((long)(data[4] * 256) + (long)(data[5] & 0xF0)))) / 16;

/* ------------------------------------------------------------ *
 * Convert the humidity data (16 bit)
 * ------------------------------------------------------------ */
   long adc_h = (data[6] * 256 + data[7]);

/* ------------------------------------------------------------ *
 * Temperature offset calculations
 * ------------------------------------------------------------ */
   float var1 = (((float)adc_t)/16384.0 - ((float)dig_T1)/1024.0)*((float)dig_T2);
   float var2 = ((((float)adc_t)/131072.0 - ((float)dig_T1)/8192.0) *
		(((float)adc_t)/131072.0 - ((float)dig_T1)/8192.0)) * ((float)dig_T3);
   float t_fine = (long)(var1 + var2);

/* ------------------------------------------------------------ *
 * temp_ptr = Temperature, fTemp = Farenheit, if we ever need it
 * ------------------------------------------------------------ */
   *temp_ptr = (var1 + var2)/5120.0;
   if(verbose == 1) printf("Debug: Temperature: [%.2f*C]\n", *temp_ptr);
   //float fTemp = *temp_ptr * 1.8 + 32;

/* ------------------------------------------------------------ *
 * Pressure offset calculations
 * ------------------------------------------------------------ */
   var1 = ((float)t_fine / 2.0) - 64000.0;
   var2 = var1 * var1 * ((float)dig_P6) / 32768.0;
   var2 = var2 + var1 * ((float)dig_P5) * 2.0;
   var2 = (var2 / 4.0) + (((float)dig_P4) * 65536.0);
   var1 = (((float)dig_P3) * var1 * var1/524288.0 + ((float)dig_P2) * var1)/524288.0;
   var1 = (1.0 + var1 / 32768.0) * ((float)dig_P1);
   float p = 1048576.0 - (float)adc_p;
   p = (p - (var2/4096.0)) * 6250.0/var1;
   var1 = ((float)dig_P9) * p * p/2147483648.0;
   var2 = p * ((float) dig_P8) / 32768.0;

/* ------------------------------------------------------------ *
 * Pressure in Pascal (divide by 100 to get hPa)
 * ------------------------------------------------------------ */
   *bmpr_ptr = (p + (var1+var2 + ((float)dig_P7))/16.0);
   if(verbose == 1) printf("Debug: Pressure: [%.2fPa]\n", *bmpr_ptr);

/* ------------------------------------------------------------ *
 * Humidity offset calculations
 * ------------------------------------------------------------ */
   float var_H = (((float)t_fine) - 76800.0);
   var_H = (adc_h - (dig_H4 * 64.0 + dig_H5 / 16384.0 * var_H)) *
   (dig_H2 / 65536.0 * (1.0 + dig_H6 / 67108864.0 * var_H *
   (1.0 + dig_H3 / 67108864.0 * var_H)));
   *humi_ptr = var_H * (1.0 -  dig_H1 * var_H / 524288.0);

   if(*humi_ptr > 100.0) *humi_ptr = 100.0;
   else if(*humi_ptr < 0.0) *humi_ptr = 0.0;

   if(verbose == 1) printf("Debug: Rel Humidity: [%.2f%%]\n", *humi_ptr);
   return(0);
}
