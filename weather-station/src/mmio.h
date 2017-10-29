/* ------------------------------------------------------------ *
 * file:        mmio.h                                          *
 * purpose:     Simple fast memory-mapped GPIO library for the  *
 *              Raspberry Pi.                                   *
 *              Maps the Raspberry Pi GIO into memory.          *
 *              Check for GPIO and peripheral addresses from    *
 *              the Raspberry Pi device tree.                   *
 *                                                              *
 * Requires:    Raspberry Pi, mmio.c                            *
 *                                                              *
 * author:      06/23/2017 Frank4DD                             *
 *              after code from Adafruit Tony DiCola            *
 *              after Gert van Loo & Dom http://elinux.org/     *
 *              https://raspberry-gpio-python.sourceforge.io/   *
 * ------------------------------------------------------------ */
#define MMIO_SUCCESS 0
#define MMIO_ERROR_DEVMEM -1
#define MMIO_ERROR_MMAP -2
#define MMIO_ERROR_OFFSET -3

extern volatile uint32_t* pi_2_mmio_gpio;

int pi_2_mmio_init(void);

static inline void pi_2_mmio_set_input(const int gpio_number) {
  // Set GPIO register to 000 for specified GPIO number.
  *(pi_2_mmio_gpio+((gpio_number)/10)) &= ~(7<<(((gpio_number)%10)*3));
}

static inline void pi_2_mmio_set_output(const int gpio_number) {
  // First set to 000 using input function.
  pi_2_mmio_set_input(gpio_number);
  // Next set bit 0 to 1 to set output.
  *(pi_2_mmio_gpio+((gpio_number)/10)) |=  (1<<(((gpio_number)%10)*3));
}

static inline void pi_2_mmio_set_high(const int gpio_number) {
  *(pi_2_mmio_gpio+7) = 1 << gpio_number;
}

static inline void pi_2_mmio_set_low(const int gpio_number) {
  *(pi_2_mmio_gpio+10) = 1 << gpio_number;
}

static inline uint32_t pi_2_mmio_input(const int gpio_number) {
  return *(pi_2_mmio_gpio+13) & (1 << gpio_number);
}
