/* ------------------------------------------------------------ *
 * file:        sensor-am2302.c                                 *
 * purpose:     Extract sensor data from AOSong DHT11/22 and    *
 *              AM2302  modules. Uses the proprietary one-wire  *
 *              bus signalling. Gets temperature and humidity.  *
 *              and writes it to global variables temp and humi *
 *                                                              *
 * Parameters:  type - supports the following AOSong modules:   *
 *              DHT11, DHT22 (also covers AM2302).              *
 *                                                              *
 *              pin - The Raspberry Pi pin number the sensors   *
 *              data line connects to, e.g. 7.                  *
 *                                                              *
 * Return Code:	Returns 0 on success, and -1 on error.          *
 *                                                              *
 * author:      06/23/2017 Frank4DD                             *
 *              after code from Adafruit Tony DiCola            *
 *                                                              *
 * compile: gcc sensor-am2302.c sensor-am2302.o                 *
 * ------------------------------------------------------------ */
#include <stdio.h>
#include <errno.h>
#include <sched.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include "mmio.h"

/* ------------------------------------------------------------ *
 * Define errors and return values.
 * ------------------------------------------------------------ */
#define DHT_ERROR_TIMEOUT -1
#define DHT_ERROR_CHECKSUM -2
#define DHT_ERROR_ARGUMENT -3
#define DHT_ERROR_GPIO -4
#define DHT_SUCCESS 0

/* ------------------------------------------------------------ *
 * Define sensor types.
 * ------------------------------------------------------------ */
#define DHT11 11
#define DHT22 22
#define AM2302 22

/* ------------------------------------------------------------ *
 * Max time to spin in a loop before bailing out considering 
 * read timeout. 32000 is suitable for a Pi or Beaglebone. 
 * ------------------------------------------------------------ */
#define DHT_MAXCOUNT 32000

/* ------------------------------------------------------------ *
 * Number of bit pulses. The first pulse is a constant 50 micros
 * pulse, following 40 pulses to represent the data afterwards.
 * ------------------------------------------------------------ */
#define DHT_PULSES 41

/* ------------------------------------------------------------ *
 * Busy wait delay for most accurate timing, but high CPU usage.
 * Only for short periods (a few hundred milliseconds at most!)
 * ------------------------------------------------------------ */
extern void busy_wait_milliseconds(uint32_t millis);

/* ------------------------------------------------------------ *
 * General delay that sleeps so CPU usage is low, accuracy is bad.
 * ------------------------------------------------------------ */
extern void sleep_milliseconds(uint32_t millis);

/* ------------------------------------------------------------ *
 * Increase scheduling priority, try to get 'real time' results.
 * ------------------------------------------------------------ */
extern void set_max_priority(void);

/* ------------------------------------------------------------ *
 * Drop scheduling priority back to normal/default.
 * ------------------------------------------------------------ */
extern void set_default_priority(void);

void busy_wait_milliseconds(uint32_t millis) {
   // Set delay time period.
   struct timeval deltatime;
   deltatime.tv_sec = millis / 1000;
   deltatime.tv_usec = (millis % 1000) * 1000;
   struct timeval walltime;
   // Get current time and add delay to find end time.
   gettimeofday(&walltime, NULL);
   struct timeval endtime;
   timeradd(&walltime, &deltatime, &endtime);
   // Tight loop to waste time (and CPU) until enough time as elapsed.
   while (timercmp(&walltime, &endtime, <)) {
      gettimeofday(&walltime, NULL);
   }
}

void sleep_milliseconds(uint32_t millis) {
   struct timespec sleep;
   sleep.tv_sec = millis / 1000;
   sleep.tv_nsec = (millis % 1000) * 1000000L;
   while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) && errno == EINTR);
}

void set_max_priority(void) {
   struct sched_param sched;
   memset(&sched, 0, sizeof(sched));
   // Use FIFO scheduler with highest priority for the lowest chance of the kernel context switching.
   sched.sched_priority = sched_get_priority_max(SCHED_FIFO);
   sched_setscheduler(0, SCHED_FIFO, &sched);
}

void set_default_priority(void) {
   struct sched_param sched;
   memset(&sched, 0, sizeof(sched));
   // Go back to default scheduler with default 0 priority.
   sched.sched_priority = 0;
   sched_setscheduler(0, SCHED_OTHER, &sched);
}

int read_am2302(int type, int pin, float *temp_ptr, float *humi_ptr, int verbose) {
   /* ------------------------------------------------------------ *
    * Initialize GPIO library.
    * ------------------------------------------------------------ */
   if (pi_2_mmio_init()<0) {
      if(verbose == 1) printf("Debug: Error - Cannot initialize GPIO memory\n");
      return DHT_ERROR_GPIO;
   }

   /* ------------------------------------------------------------ *
    * Count DHT bit pulse low and high, start at zero.
    * ------------------------------------------------------------ */
   int pulseCounts[DHT_PULSES*2] = {0};
 
   /* ------------------------------------------------------------ *
    * Set pin to output.
    * ------------------------------------------------------------ */
   pi_2_mmio_set_output(pin);
 
   /* ------------------------------------------------------------ *
    * get highest possible process priority to be more 'real time'.
    * ------------------------------------------------------------ */
   set_max_priority();
 
   /* ------------------------------------------------------------ *
    * Set pin high for ~500 milliseconds.
    * ------------------------------------------------------------ */
   pi_2_mmio_set_high(pin);
   sleep_milliseconds(500);
 
   /* ------------------------------------------------------------ *
    * The next calls are timing critical, be careful about code now
    * Set pin low for ~20 milliseconds.
    * ------------------------------------------------------------ */
   pi_2_mmio_set_low(pin);
   busy_wait_milliseconds(20);
 
   /* ------------------------------------------------------------ *
    * Set pin as input.
    * ------------------------------------------------------------ */
   pi_2_mmio_set_input(pin);
 
   /* ------------------------------------------------------------ *
    * Create a very short delay before we can read a value
    * ------------------------------------------------------------ */
   int i;
   for (i=0; i<50; ++i) { }
 
   /* ------------------------------------------------------------ *
    * Wait for DHT to pull pin low, marking the start of data
    * ------------------------------------------------------------ */
   uint32_t count = 0;
   while (pi_2_mmio_input(pin)) {
      if (++count >= DHT_MAXCOUNT) {
         // We reached the timeout waiting for response.
         // reduce priority back to normal
         set_default_priority();
         if(verbose == 1) printf("Debug: Error - Cannot get a DHT start response from pin %d\n", pin);
         return DHT_ERROR_TIMEOUT;
      }
   }
 
   /* ------------------------------------------------------------ *
    * Record pulse widths for the expected result bits.
    * ------------------------------------------------------------ */
   for (i=0; i < DHT_PULSES*2; i+=2) {
      // Count how long pin is low and store in pulseCounts[i]
      while (!pi_2_mmio_input(pin)) {
         if (++pulseCounts[i] >= DHT_MAXCOUNT) {
            // Timeout waiting for response.
            set_default_priority();
            if(verbose == 1) printf("Debug: Error - Cannot get a DHT pulse response from pin %d\n", pin);
            return DHT_ERROR_TIMEOUT;
         }
     }
      /* --------------------------------------------------------- *
       * Count how long pin is high and store in pulseCounts[i+1]
       * --------------------------------------------------------- */
      while (pi_2_mmio_input(pin)) {
         if (++pulseCounts[i+1] >= DHT_MAXCOUNT) {
            // Timeout waiting for response.
            set_default_priority();
            if(verbose == 1) printf("Debug: Error - Cannot get a DHT high pulse from pin %d\n", pin);
            return DHT_ERROR_TIMEOUT;
         }
      }
   }
 
   /* ------------------------------------------------------------ *
    * End of timing critical coderestore normal priority.
    * ------------------------------------------------------------ */
   set_default_priority();
 
   /* ------------------------------------------------------------ *
    * Compute the average low pulse width using 50 us reference
    * Ignore the first two, they are constant 80 us markers
    * ------------------------------------------------------------ */
   uint32_t threshold = 0;
   for (i=2; i < DHT_PULSES*2; i+=2) {
      threshold += pulseCounts[i];
   }
   threshold /= DHT_PULSES-1;
 
   /* ------------------------------------------------------------ *
    * Identify high pulse as 0 or 1 by comparing it to the 50us 
    * reference. If count is less than 50us its a ~28us 0 pulse,
    * if it's higher then it must be a ~70us 1 pulse.
    * ------------------------------------------------------------ */
   uint8_t data[5] = {0};
   for (i=3; i < DHT_PULSES*2; i+=2) {
      int index = (i-3)/16;
      data[index] <<= 1;
      if (pulseCounts[i] >= threshold) {
         // One bit for long pulse.
         data[index] |= 1;
      }
      // Else zero bit for short pulse.
   }
 
   // Useful debug info:
   if(verbose == 1) printf("Data: 0x%x 0x%x 0x%x 0x%x 0x%x\n", data[0], data[1], data[2], data[3], data[4]);
 
   /* ------------------------------------------------------------ *
    * Verify checksum of received data.
    * ------------------------------------------------------------ */
   if (data[4] == ((data[0] + data[1] + data[2] + data[3]) & 0xFF)) {
      if (type == DHT11) {
         // Get humidity and temp for DHT11 sensor.
         *humi_ptr = (float)data[0];
         *temp_ptr = (float)data[2];
      }
      else if (type == DHT22) {
         // Get humidity and temp for DHT22 sensor.
         *humi_ptr = (data[0] * 256 + data[1]) / 10.0f;
         *temp_ptr = ((data[2] & 0x7F) * 256 + data[3]) / 10.0f;
         if (data[2] & 0x80) *temp_ptr *= -1.0f;
      }
      if(verbose == 1) printf("Debug: Temperature: [%.2f%%]\n", *temp_ptr);
      if(verbose == 1) printf("Debug: Rel Humidity: [%.2f%%]\n", *humi_ptr);
      return DHT_SUCCESS;
   }
   else {
      if(verbose == 1) printf("Debug: Error - DHT data checksum error from pin %d\n", pin);
      return DHT_ERROR_CHECKSUM;
   }
}
