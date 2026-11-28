#ifndef __GEO_H__
#define __GEO_H__

#include "server.h"

/* Structures used inside geo.c in order to represent points and array of
 * points on the earth. */
typedef struct geoPoint {
    double longitude;
    double latitude;
    double dist;
    double score;
    /* The member, either owned by this array or borrowed from the sorted set
     * it was collected from. geoArray.owned says which, for every point in
     * the array at once, because a single command collects from a single
     * key and so from a single encoding. Borrowed members are not NUL
     * terminated: always pair this with 'memberlen'. */
    char *member;
    size_t memberlen;
} geoPoint;

typedef struct geoArray {
    struct geoPoint *array;
    size_t buckets;
    size_t used;
    int owned;  /* Members are sds this array must free. See geoPoint. */
} geoArray;

#endif
