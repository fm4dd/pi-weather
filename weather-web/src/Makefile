include ../etc/pi-web.conf
CC=gcc
CFLAGS= -O3 -Wall -g -Wno-deprecated-declarations
AR=ar
ifndef BINDIR
	BINDIR="${pi-web-data}/bin"
endif

ALLBIN=daytcalc outlier momimax
ALLSH=rrdupdate.sh solarupdate.sh

all: ${ALLBIN}

install:
	@echo -n "Checking for bin directory ${BINDIR}:"
	@if test -d ${BINDIR}; then \
		echo " ..OK. ${BINDIR} exists."; \
	else \
		install -v -d ${BINDIR}; \
		echo " ..OK. ${BINDIR} created."; \
	fi
	install -v --mode=750 --owner=root --strip ${ALLBIN} ${BINDIR}
	@echo
	@echo "Programs ${ALLBIN} installed in ${BINDIR}."
	@echo
	install -v --mode=750 --owner=root ${ALLSH} ${BINDIR}
	@echo
	@echo "Scripts ${ALLSH} installed in ${BINDIR}."

clean:
	rm -f *.o ${ALLBIN}

daytcalc: daytcalc.o
	$(CC) daytcalc.o -o daytcalc -lm

outlier: outlier.o
	$(CC) outlier.o -o outlier -lrrd

momimax: momimax.o
	$(CC) momimax.o -o momimax -lrrd
