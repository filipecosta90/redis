STD=
WARN= -Wall
OPT= -Os

R_CFLAGS= $(STD) $(WARN) $(OPT) $(DEBUG) $(CFLAGS)
R_LDFLAGS= $(LDFLAGS)
DEBUG= -g

R_CC=$(CC) $(R_CFLAGS)
R_LD=$(CC) $(R_LDFLAGS)

tdigest.o: tdigest.h tdigest.c

tdigest_example: tdigest.o tdigest_example.o
	$(R_LD) -o $@ $^ -lm

.c.o:
	$(R_CC) -c  $<  -lm

clean:
	rm -f tdigest_example *.o
