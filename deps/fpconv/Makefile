STD=
WARN= -Wall
OPT= -O2

R_CFLAGS= $(STD) $(WARN) $(OPT) $(DEBUG) $(CFLAGS)
R_LDFLAGS= $(LDFLAGS)
DEBUG= -g

R_CC=$(CC) $(R_CFLAGS)
R_LD=$(CC) $(R_LDFLAGS)

AR= ar
ARFLAGS= rcs

libfpconv.a: fpconv_dtoa.o
	$(AR) $(ARFLAGS) $@ $+

fpconv_dtoa.o: fpconv_dtoa.h fpconv_dtoa.c

.c.o:
	$(R_CC) -c  $<

# Standalone correctness + throughput microbenchmark. Not part of the
# default build (libfpconv.a) or of the redis-server link -- build/run
# explicitly with `make bench && ./bench_fpconv`. Same $(OPT) as production
# so the numbers reflect what actually ships. No dependencies beyond libc.
bench: bench_fpconv

bench_fpconv: bench_fpconv.c fpconv_dtoa.o fpconv_dtoa.h
	$(R_CC) -o $@ bench_fpconv.c fpconv_dtoa.o

clean:
	rm -f *.o
	rm -f *.a
	rm -f bench_fpconv

.PHONY: bench


