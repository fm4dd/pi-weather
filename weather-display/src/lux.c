#include "tsl2561.h"
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
	int address = 0x39;
	char *i2c_device = "/dev/i2c-1";

	void *tsl = tsl2561_init(address, i2c_device);
	tsl2561_enable_autogain(tsl);
	tsl2561_set_integration_time(tsl, TSL2561_INTEGRATION_TIME_13MS);
 
	if(tsl == NULL){ // check if error is present
		exit(1);
	} 
	
	long lux = 0;
	lux = tsl2561_lux(tsl);
	//printf("%lu\n", lux);
	
	tsl2561_close(tsl);
	i2c_device = NULL;
	return lux;
}
