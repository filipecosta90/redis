#include <stdio.h>
#include "tdigest.h"

#define SIZE 4

typedef struct TDigest TDigest_t;


int main() {
  int values[4] = { 80, 800, 5, 613 };

  TDigest_t *tdigest = tdigestNew(400);
  for (int i = 0; i < SIZE; ++i) {
    tdigestAdd(tdigest, values[i], 1);
  }

  for (int i = 0; i < SIZE; ++i) {
    printf("value %d is at percentile %f\n", values[i], tdigestCDF(tdigest, values[i]));
  }
  printf("\n");
  for (int i = 0; i <= 100; i+=10) {
    printf("%d percent has value %f\n", i, tdigestQuantile(tdigest, i / 100.0));
  }
}