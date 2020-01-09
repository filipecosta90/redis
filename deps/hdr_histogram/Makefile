STD=
WARN= -Wall
OPT= -Os

R_CFLAGS= $(STD) $(WARN) $(OPT) $(DEBUG) $(CFLAGS)
R_LDFLAGS= $(LDFLAGS)

R_CC=$(CC) $(R_CFLAGS)
R_LD=$(CC) $(R_LDFLAGS)

hdr_histogram_log.o: hdr_histogram_log.h hdr_histogram_log.c hdr_histogram.o

hdr_histogram.o: hdr_histogram.h hdr_histogram.c

hdr_histogram_example: hdr_histogram.o hdr_histogram_log.o hdr_histogram_example.o
	$(R_LD) -o $@ $^ -lm

.c.o:
	$(R_CC) -c  $<  -lm

clean:
	rm -f hdr_histogram_example *.o
