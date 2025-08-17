STD= -std=c99
WARN= -Wall
OPT= -Os

# Use REDIS_CFLAGS if provided, otherwise fall back to default optimization
ifdef REDIS_CFLAGS
R_CFLAGS= $(STD) $(WARN) $(DEBUG) $(REDIS_CFLAGS) $(CFLAGS) -DHDR_MALLOC_INCLUDE=\"hdr_redis_malloc.h\"
else
R_CFLAGS= $(STD) $(WARN) $(OPT) $(DEBUG) $(CFLAGS) -DHDR_MALLOC_INCLUDE=\"hdr_redis_malloc.h\"
endif
R_LDFLAGS= $(LDFLAGS)
DEBUG= -g

R_CC=$(CC) $(R_CFLAGS)
R_LD=$(CC) $(R_LDFLAGS)

AR= ar
ARFLAGS= rcs

libhdrhistogram.a: hdr_histogram.o
	$(AR) $(ARFLAGS) $@ $+

hdr_histogram.o: hdr_histogram.h hdr_histogram.c

.c.o:
	$(R_CC) -c  $< 

clean:
	rm -f *.o
	rm -f *.a


