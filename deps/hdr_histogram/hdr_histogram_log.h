/**
 * hdr_histogram_log.h
 * Copyright (c) 2012, 2013, 2014 Gil Tene
 * Copyright (c) 2014 Michael Barker
 * Copyright (c) 2014 Matt Warren
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/time.h>

#ifdef USE_ZLIB
#include <zlib.h>
#endif

#ifndef HDR_HISTOGRAM_H_LOG
#define HDR_HISTOGRAM_H_LOG 1

#define HDR_COMPRESSION_COOKIE_MISMATCH -29999
#define HDR_ENCODING_COOKIE_MISMATCH -29998
#define HDR_DEFLATE_INIT_FAIL -29997
#define HDR_DEFLATE_FAIL -29996
#define HDR_INFLATE_INIT_FAIL -29995
#define HDR_INFLATE_FAIL -29994
#define HDR_LOG_INVALID_VERSION -29993
#define HDR_COMPRESSION_LIBRARY_MISSING -29992


#ifdef __cplusplus
extern "C" {
#endif

int hdr_decode(uint8_t *b, size_t len, struct hdr_histogram **h);

int hdr_encode_uncompressed(struct hdr_histogram *h, uint8_t **ch, int *len);

int hdr_decode_uncompressed(uint8_t *b, size_t len, struct hdr_histogram **h);

#ifdef USE_ZLIB
int hdr_encode_compressed(struct hdr_histogram *h, uint8_t **ch, int *len);
int hdr_decode_compressed(uint8_t *b, size_t len, struct hdr_histogram **h);
#endif

/**
 * Write the header to the log, this will constist of a user defined string,
 * the current timestamp, version information and the CSV header.
 *
 * @param writer 'This' pointer
 * @param file The stream to output the log header to.
 * @param user_prefix User defined string to include in the header.
 * @param timestamp The start time that the histogram started recording from.
 * @return Will return 0 if it successfully completed or an error number if there
 * was a failure.  EIO if the write failed.
 */
int hdr_log_write_header(
        FILE *file,
        const char *user_prefix,
        struct timespec *timestamp);

/**
 * Write an hdr_histogram entry to the log.  It will be encoded in a similar
 * fashion to the approach used by the Java version of the HdrHistogram.  It will
 * be a CSV line consisting of <start timestamp>,<end timestamp>,<max>,<histogram>
 * where <histogram> is the binary histogram gzip compressed and base64 encoded.
 *
 * Timestamp is a bit of misnomer for the start_timestamp and end_timestamp values
 * these could be offsets, e.g. start_timestamp could be offset from process start
 * time and end_timestamp could actually be the length of the recorded interval.
 *
 * @param writer 'This' pointer
 * @param file The stream to write the entry to.
 * @param start_timestamp The start timestamp to include in the logged entry.
 * @param end_timestamp The end timestamp to include in the logged entry.
 * @param histogram The histogram to encode and log.
 * @return Will return 0 if it successfully completed or an error number if there
 * was a failure.  Errors include HDR_DEFLATE_INIT_FAIL, HDR_DEFLATE_FAIL if
 * something when wrong during gzip compression.  ENOMEM if we failed to allocate
 * or reallocate the buffer used for encoding (out of memory problem).  EIO if
 * write failed.
 */
int hdr_log_write(
        FILE *file,
        const struct timespec *start_timestamp,
        const struct timespec *end_timestamp,
        struct hdr_histogram *histogram);

struct hdr_log_reader {
    int major_version;
    int minor_version;
    struct timespec start_timestamp;
};

/**
 * Initialise the log reader.
 *
 * @param reader 'This' pointer
 * @return 0 on success
 */
int hdr_log_reader_init(struct hdr_log_reader *reader);

/**
 * Reads the the header information from the log.  Will capure information
 * such as version number and start timestamp from the header.
 *
 * @param hdr_log_reader 'This' pointer
 * @param file The data stream to read from.
 * @return 0 on success.  An error number on failure.
 */
int hdr_log_read_header(struct hdr_log_reader *reader, FILE *file);

/**
 * Reads an entry from the log filling in the specified histogram, timestamp and
 * interval values.  If the supplied pointer to the histogram for this method is
 * NULL then a new histogram will be allocated for the caller, however it will
 * become the callers responsibility to free it later.  If the pointer is non-null
 * the histogram read from the log will be merged with the supplied histogram.
 *
 * @param reader 'This' pointer
 * @param file The stream to read the histogram from.
 * @param histogram Pointer to allocate a histogram to or merge into.
 * @param timestamp The first timestamp from the CSV entry.
 * @param interval The second timestamp from the CSV entry
 * @return Will return 0 on success or an error number if there was some wrong
 * when reading in the histogram.  HDR_INFLATE_INIT_FAIL or HDR_INFLATE_FAIL if
 * there was a problem with Gzip.  HDR_COMPRESSION_COOKIE_MISMATCH or
 * HDR_ENCODING_COOKIE_MISMATCH if the cookie values are incorrect.
 * HDR_LOG_INVALID_VERSION if the log can not be parsed.  ENOMEM if buffer space
 * or the histogram can not be allocated.  EIO if there was an error during
 * the read.  EINVAL in any input values are incorrect.
 */
int hdr_log_read(
        struct hdr_log_reader *reader, FILE *file, struct hdr_histogram **histogram,
        struct timespec *timestamp, struct timespec *interval);

/**
 * Returns a string representation of the error number.
 *
 * @param errnum The error response from a previous call.
 * @return The user readable representation of the error.
 */
const char *hdr_strerror(int errnum);


int base64_encode(
        const uint8_t *input, size_t input_len, char *output, size_t output_len);
        
size_t base64_encoded_len(size_t decoded_size);

#ifdef __cplusplus
}
#endif

#endif
