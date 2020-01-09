#include "hdr_histogram.h"
#include "hdr_histogram_log.h"
#include "sds.h" 

#include <stdio.h>

struct hdr_histogram* histogram;

int main() {
    printf("Hello, world!\n");
// This example Histogram could be used to track and analyze the counts of 
// observed integer values between 0 us and 30000000 us ( 30 secs ) 
// while maintaining a value precision of 3 significant digits across that range,
// translating to a value resolution of :
//   - 1 microsecond up to 1 millisecond, 
//   - 1 millisecond (or better) up to one second, 
//   - 1 second (or better) up to it's maximum tracked value ( 30 seconds ).
// Initialise the histogram
//  Value quantization within the range will thus be no larger than 1/1,000th (or 0.1%) of any value.
hdr_init(
    1,  // Minimum value
    INT64_C(1000000),  // Maximum value
    3,  // Number of significant figures
    &histogram);  // Pointer to initialise

int value = 312;
// Record value
hdr_record_value(
    histogram,  // Histogram to record to
    value);  // Value to record

// Record value n times
value = 20;
hdr_record_values(
    histogram,  // Histogram to record to
    value,  // Value to record
    10);  // Record value 10 times

// Record value with correction for co-ordinated omission.
hdr_record_corrected_value(
    histogram,  // Histogram to record to
    value,  // Value to record
    1000);  // Record with expected interval of 1000.

// Print out the values of the histogram
hdr_percentiles_print(
    histogram,
    stdout,  // File to write to
    1,  // Granularity of printed values
    1.0,  // Multiplier for results
    CLASSIC);  // Format CLASSIC/CSV supported.
    
    int64_t min = hdr_min(histogram);
    double p25 = hdr_value_at_percentile(histogram, 25.0 );
    double mean = hdr_mean(histogram);
    double p75 = hdr_value_at_percentile(histogram, 75.0 );
    double p90 = hdr_value_at_percentile(histogram, 90.0 );
    double p95 = hdr_value_at_percentile(histogram, 95.0 );
    double p99 = hdr_value_at_percentile(histogram, 99.0 );
    double p999 = hdr_value_at_percentile(histogram, 99.9 );
    double p9999 = hdr_value_at_percentile(histogram, 99.99 );
    double p99999 = hdr_value_at_percentile(histogram, 99.999 );
    double p999999 = hdr_value_at_percentile(histogram, 99.9999 );
    int64_t max = hdr_max(histogram);
    printf("Min %ld\n",min);
    printf("p25 %f p50 %f p75 %f p90 %f p95 %f p99 %f p999 %f p9999 %f p99999 %f p999999 %f\n",p25,mean,p75,p90,p95,p99,p999,p9999,p99999,p999999);
    printf("Max %   ld\n",max);


  uint8_t * buffer = NULL;
      size_t len = 0;
            size_t encoded_len = 0;

    int rc = 0;

sds mystring = sdsnew("Hello World!");
printf("%s\n", mystring);
sdsfree(mystring);


// Print out the values of the histogram
hdr_percentiles_print_prometheus(
    histogram,
    stdout,  // File to write to
    1,  // Granularity of printed values
    1.0,  // Multiplier for results
    "test_histogram");  // metric name
   
   

    return 0;
}