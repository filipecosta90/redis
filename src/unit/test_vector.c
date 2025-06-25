/*
 * Copyright (c) 2009-2012, Salvatore Sanfilippo <antirez at gmail dot com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include "../vector.h"

#include "test_help.h"

typedef struct {
    uint8_t uint8;
    uint64_t uint64;
} test_struct;

int test_vector(int argc, char **argv, int flags) {
    UNUSED(argc);
    UNUSED(argv);
    UNUSED(flags);

    /* The test cases cover the following scenarios:
     * 1) Whether the array pre-allocates memory during initialization;
     * 2) Element sizes smaller than, equal to, and larger than sizeof(void*);
     * 3) Usage of each API.
     */
    vector uint8_vector;
    vector uint64_vector;
    vector struct_vector;
    vectorInit(&uint8_vector, 0, sizeof(uint8_t));
    vectorInit(&uint64_vector, 10, sizeof(uint64_t));
    vectorInit(&struct_vector, 128, sizeof(test_struct));

    for (uint64_t i = 0; i < 128; i++) {
        uint8_t *uint8_item = vectorPush(&uint8_vector);
        *uint8_item = i;

        uint64_t *uint64_item = vectorPush(&uint64_vector);
        *uint64_item = i * 1000;

        test_struct *struct_item = vectorPush(&struct_vector);
        struct_item->uint8 = i;
        struct_item->uint64 = i * 1000;
    }

    TEST_ASSERT_MESSAGE("uint8_vector length", vectorLen(&uint8_vector) == 128);
    TEST_ASSERT_MESSAGE("uint64_vector length", vectorLen(&uint64_vector) == 128);
    TEST_ASSERT_MESSAGE("struct_vector length", vectorLen(&struct_vector) == 128);
    for (uint32_t i = 0; i < vectorLen(&uint8_vector); i++) {
        uint8_t *uint8_item = vectorGet(&uint8_vector, i);
        TEST_ASSERT_MESSAGE("uint8_item value", *uint8_item == i);

        uint64_t *uint64_item = vectorGet(&uint64_vector, i);
        TEST_ASSERT_MESSAGE("uint64_item value", *uint64_item == i * 1000);

        test_struct *struct_item = vectorGet(&struct_vector, i);
        TEST_ASSERT_MESSAGE("struct_item uint8 value", struct_item->uint8 == i);
        TEST_ASSERT_MESSAGE("struct_item uint64 value", struct_item->uint64 == i * 1000);
    }

    vectorCleanup(&uint8_vector);
    vectorCleanup(&uint64_vector);
    vectorCleanup(&struct_vector);
    return 0;
}
