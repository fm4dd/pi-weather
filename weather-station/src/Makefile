include ../etc/pi-weather.conf
CC=gcc
CFLAGS= -O3 -Wall -g -Wno-deprecated-declarations
AR=ar
ifndef BINDIR
	BINDIR="${pi-weather-dir}/bin"
endif

ALLBIN=getsensor daytcalc outlier momimax wcam-archive wcam-mkmovie
ALLSH=rrdupdate.sh send-data.sh send-night.sh

all: ${ALLBIN}

install:
	@echo -n "Checking for bin directory ${BINDIR}:"
	@if test -d ${BINDIR}; then \
		echo " ..OK. ${BINDIR} exists."; \
	else \
		install -v -d ${BINDIR}; \
		echo " ..OK. ${BINDIR} created."; \
	fi
	install -v --mode=750 --owner=pi --strip ${ALLBIN} ${BINDIR}
	@echo
	@echo "Programs ${ALLBIN} installed in ${BINDIR}."
	@echo
	install -v --mode=750 --owner=pi ${ALLSH} ${BINDIR}
	@echo
	@echo "Scripts ${ALLSH} installed in ${BINDIR}."

clean:
	rm -f *.o ${ALLBIN}

getsensor: getsensor.o sensor-bme280.o sensor-am2302.o sensor-bmp180.o mmio.o
	$(CC) getsensor.o sensor-bme280.o mmio.o sensor-am2302.o sensor-bmp180.o -o getsensor ${LIBS}

daytcalc: daytcalc.o
	$(CC) daytcalc.o -o daytcalc -lm

outlier: outlier.o
	$(CC) outlier.o -o outlier -lrrd

momimax: momimax.o
	$(CC) momimax.o -o momimax -lrrd

wcam-archive: wcam-archive.o
	$(CC) wcam-archive.o -o wcam-archive

wcam-mkmovie: wcam-mkmovie.o
	$(CC) wcam-mkmovie.o -o wcam-mkmovie
