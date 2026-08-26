/* bench_fpconv.c -- standalone correctness + throughput microbenchmark for
 * fpconv_dtoa(), kept alongside the library so a change to the hot digit-
 * generation loop can be timed and round-trip-checked without building all
 * of Redis. Not part of `make` / libfpconv.a -- build explicitly with
 * `make bench` and run `./bench_fpconv`. Depends on nothing beyond libc.
 */
#include "fpconv_dtoa.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#define N 2000000

static uint64_t rngstate = 88172645463325252ULL;

static uint64_t xorshift64(void) {
    rngstate ^= rngstate << 13;
    rngstate ^= rngstate >> 7;
    rngstate ^= rngstate << 17;
    return rngstate;
}

/* Distributions chosen to cover what Redis actually formats: zset scores
 * are commonly small fractions (the memtier zrange/zscore specs seed
 * scores as random floats in [0,1)), but INCRBYFLOAT/GEOPOS/etc. produce
 * integers and a wide range of magnitudes, so mix those in too. */
static double gen_value(long i) {
    uint64_t r = xorshift64();
    double frac = (double)(r % 1000000000ULL) / 1000000000.0;
    int mode = i % 6;
    switch (mode) {
    case 0: return frac;                 /* [0,1) -- typical zset score */
    case 1: return frac * 1e10;
    case 2: return frac * 1e-10;
    case 3: return (double)(int64_t)(r % 1000000);  /* integer-valued */
    case 4: return frac * 1e300;         /* scientific-notation range */
    default: return -frac * 1000.0;      /* negative */
    }
}

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

int main(void) {
    double *vals = malloc(sizeof(double) * N);
    if (!vals) {
        fprintf(stderr, "out of memory\n");
        return 2;
    }
    for (long i = 0; i < N; i++) vals[i] = gen_value(i);

    /* Correctness: fpconv_dtoa() promises the shortest decimal that
     * round-trips back to the same double. strtod() must recover it
     * exactly for every value, including the edge cases below. */
    char buf[24];
    long mismatches = 0, reported = 0;
    for (long i = 0; i < N; i++) {
        int len = fpconv_dtoa(vals[i], buf);
        buf[len] = '\0';
        double back = strtod(buf, NULL);
        /* memcmp on bit pattern so -0.0 and NaN payloads aren't masked by == */
        if (memcmp(&back, &vals[i], sizeof(double)) != 0) {
            mismatches++;
            if (reported < 5) {
                fprintf(stderr, "round-trip mismatch: %.20g -> \"%s\" -> %.20g\n",
                        vals[i], buf, back);
                reported++;
            }
        }
    }

    static const double edge_cases[] = {
        0.0, -0.0, 1.0, -1.0, 3.3, 0.1, 1e300, 1e-300, 1.7976931348623157e308,
        4.9406564584124654e-324,
    };
    for (size_t i = 0; i < sizeof(edge_cases) / sizeof(edge_cases[0]); i++) {
        int len = fpconv_dtoa(edge_cases[i], buf);
        buf[len] = '\0';
        double back = strtod(buf, NULL);
        if (memcmp(&back, &edge_cases[i], sizeof(double)) != 0) {
            mismatches++;
            fprintf(stderr, "round-trip mismatch (edge case): %.20g -> \"%s\" -> %.20g\n",
                    edge_cases[i], buf, back);
        }
    }

    /* Throughput. */
    volatile int sink = 0;
    double t0 = now_ns();
    for (long i = 0; i < N; i++) sink += fpconv_dtoa(vals[i], buf);
    double t1 = now_ns();

    double ns_per_call = (t1 - t0) / N;
    printf("mismatches=%ld\n", mismatches);
    printf("ns_per_call=%.2f\n", ns_per_call);
    printf("calls_per_sec=%.0f\n", 1e9 / ns_per_call);
    printf("sink=%d\n", sink);

    free(vals);
    return mismatches != 0;
}
