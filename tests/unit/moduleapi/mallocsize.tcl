set testmodule [file normalize tests/modules/mallocsize.so]


start_server {tags {"modules external:skip"}} {
    r module load $testmodule

    test {MallocSize of raw bytes} {
        assert_equal [r mallocsize.setraw key 40] {OK}
        assert_morethan [r memory usage key] 40
    }
    
    test {MallocSize of string} {
        assert_equal [r mallocsize.setstr key abcdefg] {OK}
        assert_morethan [r memory usage key] 7 ;# Length of "abcdefg"
    }
    
    test {MallocSize of dict} {
        assert_equal [r mallocsize.setdict key f1 v1 f2 v2] {OK}
        assert_morethan [r memory usage key] 8 ;# Length of "f1v1f2v2"
    }

    if {[string match {*jemalloc*} [s mem_allocator]]} {
        test {MEMORY USAGE accounts for the moduleValue wrapper} {
            # Regression test: kvobjComputeSize() must count the moduleValue
            # wrapper (moduleType* + value*) that createModuleObject() allocates
            # for every OBJ_MODULE key. Pre-fix, the wrapper was invisible to
            # `zmalloc_size(o)` (sees only the kvobj) and to `moduleGetMemUsage`
            # (sees only mv->value), so MEMORY USAGE under-reported by
            # `zmalloc_size(moduleValue)` (16 B under jemalloc's exact 16-byte
            # size class, 24 B under quantized builds).
            #
            # Allocator-portable check via aggregate MU / used_memory delta
            # ratio (mirrors the tests/unit/type/stream-cgroups.tcl regression):
            # both terms track the same underlying zmalloc allocations, so the
            # ratio is invariant to slab-class quantization. Empirical on
            # jemalloc x86_64 with N=1000 payload-40 module keys: buggy path
            # ~0.51; fixed path ~0.59. Floor 0.55 sits at the midpoint with
            # ~0.04 margin either way. Sampling `[s used_memory]` before the
            # per-key MU sweep biases the ratio slightly upward (the MEMORY
            # USAGE reply-buffer alloc is not yet in um), the safer bias
            # direction. Gated to jemalloc to hold the empirical calibration
            # invariant across build configs.
            r flushall
            # Warm the client reply-buffer high-water so a background jitter
            # spike doesn't inflate the um denominator on the first sample.
            for {set i 0} {$i < 3} {incr i} { r set warmup$i v }
            set N 1000
            set um0 [s used_memory]
            for {set i 0} {$i < $N} {incr i} { r mallocsize.setraw k$i 40 }
            set um1 [s used_memory]
            set mu_sum 0
            for {set i 0} {$i < $N} {incr i} {
                incr mu_sum [r memory usage k$i]
            }
            set um_delta [expr {$um1 - $um0}]
            assert {$um_delta > 0}
            assert {double($mu_sum) / double($um_delta) > 0.55}
            r flushall
        }
    }
}
