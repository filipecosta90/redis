#
# Tests for the parallel-fullsync-streams feature.
#
# parallel-fullsync-streams enables a multi-threaded encoder in the
# RDB fork child during diskless full sync. The wire format and the
# replica side are unchanged; the master simply fans out the keyspace
# encoding across N pthreads, each writing into its own per-thread
# buffer, then the fork-child main thread copies those buffers in
# order to the existing rdb pipe and combines per-thread CRCs into
# the final stream CRC.
#
# These tests verify functional correctness end-to-end:
#   * the replica sees the same dbsize and same DEBUG DIGEST as the
#     single-threaded path,
#   * the feature behaves identically with N = 1, 2, 4, 8 streams,
#   * disabled (N = 1) does not change behaviour,
#   * an empty database, a tiny database, and a large database all
#     work,
#   * multiple replicas attached to the same master all sync,
#   * a second full sync on the same replica works (covers the
#     re-fork path),
#   * CONFIG GET / CONFIG SET round-trip works,
#   * very large values (>>20 byte LZF threshold) compress correctly,
#   * keys with TTLs are propagated correctly.
#
# All tests use diskless socket sync (the only path the parallel
# encoder is wired into) and rely on `debug populate` to generate
# deterministic key/value pairs so that DEBUG DIGEST is meaningful.

# ----------------------------------------------------------------------
# Common helper: spin up a master/replica pair, populate the master
# with `count` keys (1 KiB values), wire diskless sync with the given
# parallel-fullsync-streams value, and assert dbsize + digest match.
# ----------------------------------------------------------------------
proc test_parallel_fullsync_basic {streams count valsize} {
    start_server {tags {"repl external:skip"}} {
        set replica [srv 0 client]
        set replica_host [srv 0 host]
        set replica_port [srv 0 port]
        start_server {} {
            set master [srv 0 client]
            set master_host [srv 0 host]
            set master_port [srv 0 port]

            $master config set save ""
            $master config set repl-diskless-sync yes
            $master config set repl-diskless-sync-delay 0
            $master config set parallel-fullsync-streams $streams
            $replica config set save ""

            if {$count > 0} {
                $master debug populate $count key $valsize
            }
            set master_dbsize [$master dbsize]
            set master_digest [$master debug digest]

            $replica replicaof $master_host $master_port
            wait_for_sync $replica

            test "parallel-fullsync streams=$streams count=$count valsize=$valsize: dbsize matches" {
                assert_equal $master_dbsize [$replica dbsize]
            }

            test "parallel-fullsync streams=$streams count=$count valsize=$valsize: digest matches" {
                assert_equal $master_digest [$replica debug digest]
            }
        }
    }
}

# ----------------------------------------------------------------------
# 1) Sweep over stream counts on a moderate dataset (10k x 1 KiB).
#    All N values should produce identical replica state.
# ----------------------------------------------------------------------
foreach streams {1 2 4 8} {
    test_parallel_fullsync_basic $streams 10000 1024
}

# ----------------------------------------------------------------------
# 2) Empty database. Edge case: 0 keys per thread.
# ----------------------------------------------------------------------
test_parallel_fullsync_basic 4 0 1024

# ----------------------------------------------------------------------
# 3) Tiny database. Each thread gets ~3 keys; some threads may get 0
#    after the hash-mod-N filter.
# ----------------------------------------------------------------------
test_parallel_fullsync_basic 4 12 1024

# ----------------------------------------------------------------------
# 4) Larger value sizes — exercises the LZF path on values that
#    benefit more from compression.
# ----------------------------------------------------------------------
test_parallel_fullsync_basic 4 1000 8192

# ----------------------------------------------------------------------
# 5) Multiple replicas off the same master. Both replicas should sync
#    successfully and end up with identical dbsize / digest as the
#    master.
# ----------------------------------------------------------------------
start_server {tags {"repl external:skip"}} {
    set replica1 [srv 0 client]
    set replica1_host [srv 0 host]
    set replica1_port [srv 0 port]
    start_server {} {
        set replica2 [srv 0 client]
        set replica2_host [srv 0 host]
        set replica2_port [srv 0 port]
        start_server {} {
            set master [srv 0 client]
            set master_host [srv 0 host]
            set master_port [srv 0 port]

            $master config set save ""
            $master config set repl-diskless-sync yes
            $master config set repl-diskless-sync-delay 0
            $master config set parallel-fullsync-streams 4
            $replica1 config set save ""
            $replica2 config set save ""

            $master debug populate 5000 key 256
            set master_dbsize [$master dbsize]
            set master_digest [$master debug digest]

            $replica1 replicaof $master_host $master_port
            $replica2 replicaof $master_host $master_port
            wait_for_sync $replica1
            wait_for_sync $replica2

            test "parallel-fullsync: two replicas attached to same master both sync" {
                assert_equal $master_dbsize [$replica1 dbsize]
                assert_equal $master_dbsize [$replica2 dbsize]
                assert_equal $master_digest [$replica1 debug digest]
                assert_equal $master_digest [$replica2 debug digest]
            }
        }
    }
}

# ----------------------------------------------------------------------
# 6) Re-sync. Verify that a second full sync on the same replica works
#    (covers the re-fork code path — the sds buffer pre-allocation
#    cap, the per-thread CRC reset, the encoder thread spawn under
#    a fresh ctx, etc).
# ----------------------------------------------------------------------
start_server {tags {"repl external:skip"}} {
    set replica [srv 0 client]
    set replica_host [srv 0 host]
    set replica_port [srv 0 port]
    start_server {} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]

        $master config set save ""
        $master config set repl-diskless-sync yes
        $master config set repl-diskless-sync-delay 0
        $master config set parallel-fullsync-streams 4
        $replica config set save ""

        $master debug populate 1000 first 256

        $replica replicaof $master_host $master_port
        wait_for_sync $replica

        test "parallel-fullsync: first sync ok" {
            assert_equal [$master dbsize] [$replica dbsize]
            assert_equal [$master debug digest] [$replica debug digest]
        }

        # Force a second full sync: detach the replica, change the
        # master's data so partial resync can't catch up, re-attach.
        $replica replicaof no one
        $master flushall
        $master debug populate 2000 second 256
        set master_dbsize [$master dbsize]
        set master_digest [$master debug digest]

        $replica flushall
        $replica replicaof $master_host $master_port
        wait_for_sync $replica

        test "parallel-fullsync: second full sync also ok" {
            assert_equal $master_dbsize [$replica dbsize]
            assert_equal $master_digest [$replica debug digest]
        }
    }
}

# ----------------------------------------------------------------------
# 7) CONFIG SET / CONFIG GET round-trip and validation.
# ----------------------------------------------------------------------
start_server {tags {"repl external:skip"}} {
    test "parallel-fullsync-streams: default value is 1" {
        assert_equal "parallel-fullsync-streams 1" [r config get parallel-fullsync-streams]
    }

    test "parallel-fullsync-streams: CONFIG SET to legal values" {
        foreach n {1 2 4 8 16} {
            r config set parallel-fullsync-streams $n
            assert_equal "parallel-fullsync-streams $n" [r config get parallel-fullsync-streams]
        }
    }

    test "parallel-fullsync-streams: CONFIG SET below range is rejected" {
        assert_error "*argument must be between 1 and 16 inclusive*" {
            r config set parallel-fullsync-streams 0
        }
    }

    test "parallel-fullsync-streams: CONFIG SET above range is rejected" {
        assert_error "*argument must be between 1 and 16 inclusive*" {
            r config set parallel-fullsync-streams 17
        }
    }
}

# ----------------------------------------------------------------------
# 8) Keys with TTL — exercises the rdbSaveKeyValuePair expire path
#    inside each encoder thread.
# ----------------------------------------------------------------------
start_server {tags {"repl external:skip"}} {
    set replica [srv 0 client]
    set replica_host [srv 0 host]
    set replica_port [srv 0 port]
    start_server {} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]

        $master config set save ""
        $master config set repl-diskless-sync yes
        $master config set repl-diskless-sync-delay 0
        $master config set parallel-fullsync-streams 4
        $replica config set save ""

        # Populate a mix of keys with and without TTL.
        for {set i 0} {$i < 500} {incr i} {
            $master set "key:no-ttl:$i" "value-$i"
        }
        for {set i 0} {$i < 500} {incr i} {
            $master set "key:ttl:$i" "value-$i" EX 3600
        }
        set master_dbsize [$master dbsize]
        set master_digest [$master debug digest]

        $replica replicaof $master_host $master_port
        wait_for_sync $replica

        test "parallel-fullsync: keys with mixed TTL replicate correctly" {
            assert_equal $master_dbsize [$replica dbsize]
            assert_equal $master_digest [$replica debug digest]
        }

        test "parallel-fullsync: TTL is preserved on the replica" {
            set ttl [$replica ttl "key:ttl:0"]
            assert {$ttl > 0 && $ttl <= 3600}
            assert_equal -1 [$replica ttl "key:no-ttl:0"]
        }
    }
}
