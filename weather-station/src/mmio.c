/* ------------------------------------------------------------ *
 * file:        mmio.c                                          *
 * purpose:     Simple fast memory-mapped GPIO library for the  *
 *              Raspberry Pi.                                   *
 *              Maps the Raspberry Pi GIO into memory.          *
 *              Check for GPIO and peripheral addresses from    *
 *              the Raspberry Pi device tree.                   *
 *                                                              *
 * Return Code: Returns 0 on success, and -1 on error.          *
 *                                                              *
 * Requires:    Raspberry Pi, mmio.h                            *
 *                                                              *
 * author:      06/23/2017 Frank4DD                             *
 *              after code from Adafruit Tony DiCola            *
 *              after Gert van Loo & Dom http://elinux.org/     *
 *              https://raspberry-gpio-python.sourceforge.io/   *
 *                                                              *
 * compile: gcc mmio.c mmio.o                                   *
 * ------------------------------------------------------------ */
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <stdint.h>
#include <unistd.h>
#include "mmio.h"

#define GPIO_BASE_OFFSET 0x200000
#define GPIO_LENGTH 4096

volatile uint32_t* pi_2_mmio_gpio = NULL;

int pi_2_mmio_init(void) {
  if (pi_2_mmio_gpio == NULL) {
    FILE *fp = fopen("/proc/device-tree/soc/ranges", "rb");
    if (fp == NULL) {
      return MMIO_ERROR_OFFSET;
    }
    fseek(fp, 4, SEEK_SET);
    unsigned char buf[4];
    if (fread(buf, 1, sizeof(buf), fp) != sizeof(buf)) {
      return MMIO_ERROR_OFFSET;
    }
    uint32_t peri_base = buf[0] << 24 | buf[1] << 16 | buf[2] << 8 | buf[3] << 0;
    uint32_t gpio_base = peri_base + GPIO_BASE_OFFSET;
    fclose(fp);

    int fd = open("/dev/gpiomem", O_RDWR | O_SYNC);
    if (fd == -1) {
      // Error opening /dev/gpiomem.
      return MMIO_ERROR_DEVMEM;
    }
    // Map GPIO memory to location in process space.
    pi_2_mmio_gpio = (uint32_t*)mmap(NULL, GPIO_LENGTH, PROT_READ | PROT_WRITE, MAP_SHARED, fd, gpio_base);
    close(fd);
    if (pi_2_mmio_gpio == MAP_FAILED) {
      // Don't save the result if the memory mapping failed.
      pi_2_mmio_gpio = NULL;
      return MMIO_ERROR_MMAP;
    }
  }
  return MMIO_SUCCESS;
}
