SENSOR=tsl2561

all:
	gcc -Wall -c $(SENSOR).c -o $(SENSOR).o -lm
	gcc -Wall $(SENSOR).o lux.c -o lux -lm

clean:
	rm *.o > /dev/null 2>&1 &
