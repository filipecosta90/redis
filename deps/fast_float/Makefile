STD= -fPIC
WARN= -Wall
OPT= -O3

R_CFLAGS= $(STD) $(WARN) $(OPT) $(DEBUG) $(CFLAGS)
R_LDFLAGS= $(LDFLAGS)
DEBUG= -g

R_CC=$(CXX) $(R_CFLAGS) 
R_LD=$(CXX) $(R_LDFLAGS)

AR= ar
ARFLAGS= rcs

libfastfloat.a: fast_float.o
	$(AR) $(ARFLAGS) $@ $+

fast_float.o: fast_double_parser.hpp fast_float.h fast_float.cpp

.c.o:
	$(R_CC) -c  $< 

clean:
	rm -f *.o
	rm -f *.a


