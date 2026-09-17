STD=
WARN= -Wall
# -O2, not -Os: at -Os gcc will not expand the strength-reduced divisions in
# generate_digits() (fpconv_dtoa.c) into multiply+shift. Read the comment on
# that loop before lowering this.
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

fpconv_dtoa.o: fpconv_dtoa.h fpconv_dtoa.c Makefile

.c.o:
	$(R_CC) -c  $< 

clean:
	rm -f *.o
	rm -f *.a


