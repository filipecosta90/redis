# Multi-pair ZADD on a B+ tree resolves its member lookups in batches and
# answers the pairs that change nothing from the batch. Exercise the batch
# path (>= 16 pairs), its boundaries, and every flag combination, and compare
# against a Tcl model of the same command.
# ZADD_BATCH_MIN_PAIRS in src/t_zset.c. Command sizes below are derived from it:
# a command shorter than this never batches, so hardcoding sizes would leave these
# tests green while covering nothing if the constant moves.
set zadd_batch_min 64
set zadd_batch_big [expr {$zadd_batch_min + 16}]   ;# spans the probe and several refills

start_server {tags {"zset"}} {
    proc zadd_batch_model {name pairs flags} {
        # Returns {added updated} for a ZADD applied to dict 'name'.
        upvar 1 $name d
        set added 0
        set updated 0
        foreach {s m} $pairs {
            set exists [dict exists $d $m]
            if {$exists} {
                set cur [dict get $d $m]
                if {[lsearch -exact $flags NX] >= 0} continue
                if {[lsearch -exact $flags GT] >= 0 && $s <= $cur} continue
                if {[lsearch -exact $flags LT] >= 0 && $s >= $cur} continue
                if {$s != $cur} {
                    dict set d $m $s
                    incr updated
                }
            } else {
                if {[lsearch -exact $flags XX] >= 0} continue
                dict set d $m $s ; incr added
            }
        }
        return [list $added $updated]
    }

    proc zadd_batch_assert_score {expected r key member} {
        set got [$r zscore $key $member]
        assert {$got ne {} && $got == $expected}
    }

    proc zadd_batch_check {r key d} {
        # Server and model must agree on cardinality and on every score.
        assert_equal [dict size $d] [$r zcard $key]
        dict for {m s} $d {
            zadd_batch_assert_score $s $r $key $m
        }
    }

    set zadd_batch_old_limit [lindex [r config get zset-max-listpack-entries] 1]

    foreach enc {listpack btree} {
        if {$enc eq "listpack"} {
            r config set zset-max-listpack-entries 512
        } else {
            r config set zset-max-listpack-entries 0
        }

        test "ZADD batch path - steady state re-send, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < 200} {incr i} { lappend pairs [expr {$i*1.5}] "m:$i:padpadpadpad" }
            r zadd zb {*}$pairs
            assert_encoding $enc zb
            # Re-sending the identical pairs must change nothing, repeatedly.
            for {set rep 0} {$rep < 5} {incr rep} {
                assert_equal 0 [r zadd zb {*}$pairs]
                assert_equal 0 [r zadd zb CH {*}$pairs]
            }
            assert_equal 200 [r zcard zb]
            for {set i 0} {$i < 200} {incr i} {
                zadd_batch_assert_score [expr {$i*1.5}] r zb "m:$i:padpadpadpad"
            }
        }

        test "ZADD batch path - model agreement across flags and sizes, $enc" {
            foreach n [list 1 2 15 16 17 31 32 33 \
                [expr {$zadd_batch_min-1}] $zadd_batch_min [expr {$zadd_batch_min+1}] \
                [expr {$zadd_batch_min+$zadd_batch_min}]] {
                foreach flags {{} {NX} {XX} {GT} {LT} {XX GT} {XX LT} {CH}} {
                    r del zb
                    set d [dict create]
                    # Seed half the members so each command mixes hits and misses.
                    set seed {}
                    for {set i 0} {$i < $n} {incr i 2} {
                        lappend seed [expr {$i+0.5}] "s:$i"
                        dict set d "s:$i" [expr {$i+0.5}]
                    }
                    if {[llength $seed]} {
                        r zadd zb {*}$seed
                        if {$n >= 16} { assert_encoding $enc zb }
                    }
                    foreach round {0 1 2} {
                        set pairs {}
                        for {set i 0} {$i < $n} {incr i} {
                            # round 0: exactly the seeded scores where seeded
                            # round 1: all scores shifted, so every hit updates
                            # round 2: back to the seeded scores
                            set s [expr {$round == 1 ? $i+900.25 : $i+0.5}]
                            lappend pairs $s "s:$i"
                        }
                        set fl [lsearch -all -inline -not -exact $flags CH]
                        lassign [zadd_batch_model d $pairs $fl] exp_added exp_updated
                        set got [r zadd zb {*}$flags {*}$pairs]
                        if {[lsearch -exact $flags CH] >= 0} {
                            assert_equal [expr {$exp_added+$exp_updated}] $got
                        } else {
                            assert_equal $exp_added $got
                        }
                        zadd_batch_check r zb $d
                    }
                    # The rounds above seed only even indices, so the leading
                    # run of unchanged pairs is never longer than one pair.
                    # Re-send the whole current state verbatim, which makes the
                    # run span every refill, and append one new member so the
                    # reply arithmetic is checked across a full-length run.
                    set pairs {}
                    dict for {m sc} $d { lappend pairs $sc $m }
                    lappend pairs 4242.5 "fresh:$n"
                    set fl [lsearch -all -inline -not -exact $flags CH]
                    lassign [zadd_batch_model d $pairs $fl] exp_added exp_updated
                    set got [r zadd zb {*}$flags {*}$pairs]
                    if {[lsearch -exact $flags CH] >= 0} {
                        assert_equal [expr {$exp_added+$exp_updated}] $got
                    } else {
                        assert_equal $exp_added $got
                    }
                    zadd_batch_check r zb $d
                }
            }
        }

        test "ZADD batch path - leading runs at the probe boundary, $enc" {
            # The first batch of a command probes a quarter of a batch, and only
            # a batch consumed to its end widens the next one. Pin runs of
            # exactly 3, 4 and 5 unchanged pairs before the first change.
            foreach k {3 4 5} {
                r del zb
                set pairs {}
                for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend pairs 1.0 "p:$i" }
                r zadd zb {*}$pairs
                assert_encoding $enc zb
                set cmd {}
                for {set i 0} {$i < $zadd_batch_big} {incr i} {
                    lappend cmd [expr {$i == $k ? 2.0 : 1.0}] "p:$i"
                }
                assert_equal 1 [r zadd zb CH {*}$cmd]
                zadd_batch_assert_score 2.0 r zb "p:$k"
                for {set i 0} {$i < $zadd_batch_big} {incr i} {
                    if {$i != $k} { zadd_batch_assert_score 1.0 r zb "p:$i" }
                }
                assert_equal $zadd_batch_big [r zcard zb]
            }
        }

        test "ZADD batch path - GEOADD reaches the same code, $enc" {
            # GEOADD routes through zaddCommand, so a multi-member GEOADD on a
            # B+ tree takes the batch path too.
            r del zg
            set args {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} {
                lappend args [expr {-20.0 + $i*1.5}] [expr {10.0 + $i*0.5}] "geo:$i"
            }
            r geoadd zg {*}$args
            assert_encoding $enc zg
            assert_equal $zadd_batch_big [r zcard zg]
            set before [r zrange zg 0 -1 WITHSCORES]
            # Re-sending the identical members must change nothing.
            assert_equal 0 [r geoadd zg {*}$args]
            assert_equal 0 [r geoadd zg CH {*}$args]
            assert_equal $before [r zrange zg 0 -1 WITHSCORES]
            # One moved member still updates, and only that one.
            assert_equal 1 [r geoadd zg CH 12.5 41.9 "geo:7"]
            assert_equal $zadd_batch_big [r zcard zg]
        }

        test "ZADD batch path - duplicate members inside one command, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend pairs 1.0 "d:$i" }
            r zadd zb {*}$pairs
            assert_encoding $enc zb
            # Same member twice: first unchanged, second changes it.
            set cmd {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend cmd 1.0 "d:$i" }
            lappend cmd 1.0 "d:3" 7.5 "d:3"
            assert_equal 0 [r zadd zb {*}$cmd]
            zadd_batch_assert_score 7.5 r zb "d:3"
            # And the reverse order: changed first, then re-sent unchanged.
            set cmd {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend cmd 1.0 "d:$i" }
            lappend cmd 9.5 "d:4" 9.5 "d:4"
            assert_equal 0 [r zadd zb {*}$cmd]
            zadd_batch_assert_score 9.5 r zb "d:4"
            zadd_batch_assert_score 1.0 r zb "d:5"
        }

        test "ZADD batch path - a bad score aborts before anything is applied, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend pairs 1.0 "n:$i" }
            r zadd zb {*}$pairs
            assert_encoding $enc zb
            # An unparsable score in the middle of a long command: scores are
            # parsed up front, so the command must apply none of its pairs.
            set cmd {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} {
                lappend cmd [expr {$i == 10 ? "notanumber" : 4.0}] "n:$i"
            }
            assert_error "*not a valid float*" {r zadd zb {*}$cmd}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { zadd_batch_assert_score 1.0 r zb "n:$i" }
            # A NaN *result* is still rejected, and INCR never takes the batch.
            r zadd zb inf "n:0"
            assert_error "*not a number*" {r zadd zb INCR -inf "n:0"}
        }

        test "ZADD batch path - unchanged pairs do not bump dirty or notify, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend pairs 2.5 "k:$i" }
            r zadd zb {*}$pairs
            assert_encoding $enc zb
            set before [s rdb_changes_since_last_save]
            for {set rep 0} {$rep < 3} {incr rep} { r zadd zb {*}$pairs }
            assert_equal $before [s rdb_changes_since_last_save]
            # One real change does bump it.
            r zadd zb 3.5 "k:7"
            assert {[s rdb_changes_since_last_save] > $before}
        }

        test "ZADD batch path - GT/LT/NX semantics across the batch boundary, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend pairs 10.0 "g:$i" }
            r zadd zb {*}$pairs
            assert_encoding $enc zb
            # GT with equal scores is a no-op; with a higher score it updates.
            set cmd {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} {
                lappend cmd [expr {$i == 20 ? 11.0 : 10.0}] "g:$i"
            }
            assert_equal 1 [r zadd zb GT CH {*}$cmd]
            zadd_batch_assert_score 11.0 r zb "g:20"
            zadd_batch_assert_score 10.0 r zb "g:19"
            # LT with a higher score changes nothing anywhere.
            set cmd {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend cmd 99.0 "g:$i" }
            assert_equal 0 [r zadd zb LT CH {*}$cmd]
            zadd_batch_assert_score 10.0 r zb "g:0"
            # NX never touches an existing member but still adds new ones.
            set cmd {}
            for {set i 0} {$i < $zadd_batch_big} {incr i} { lappend cmd 77.0 "g:$i" }
            lappend cmd 5.0 "g:new"
            assert_equal 1 [r zadd zb NX {*}$cmd]
            zadd_batch_assert_score 10.0 r zb "g:0"
            zadd_batch_assert_score 5.0 r zb "g:new"
        }

        test "ZADD batch path - survives a reload unchanged, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < 300} {incr i} { lappend pairs [expr {$i/7.0}] "r:$i" }
            r zadd zb {*}$pairs
            assert_encoding $enc zb
            r zadd zb {*}$pairs
            set before [r zrange zb 0 -1 WITHSCORES]
            r debug reload
            assert_equal $before [r zrange zb 0 -1 WITHSCORES]
        } {} {needs:debug}
    }
    r config set zset-max-listpack-entries $zadd_batch_old_limit

    # The gate reads the encoding after zsetTypeMaybeConvert(), so a ZADD long
    # enough to convert a listpack key engages the batch on the set it has just
    # converted, and zbtreeShrinkToFit() then runs on a command that answered
    # pairs from a batch. Reachable on the default config; exercise it there.
    test "ZADD batch path - a converting ZADD batches the set it just converted" {
        # Must run at the shipped default, which is what makes this path reachable
        # in production; 128 is src/config.c's createIntConfig default.
        assert_equal 128 $zadd_batch_old_limit
        r del zc
        set seed {}
        for {set i 0} {$i < 20} {incr i} { lappend seed [expr {$i+0.25}] "c:$i" }
        r zadd zc {*}$seed
        assert_encoding listpack zc
        # 140 pairs: the first 20 re-send the listpack members at their current
        # scores, the rest are new. 140 > 128 so the key converts first.
        set cmd $seed
        for {set i 20} {$i < 140} {incr i} { lappend cmd [expr {$i+0.25}] "c:$i" }
        assert_equal 120 [r zadd zc {*}$cmd]
        assert_encoding btree zc
        assert_equal 140 [r zcard zc]
        for {set i 0} {$i < 140} {incr i} {
            zadd_batch_assert_score [expr {$i+0.25}] r zc "c:$i"
        }
        # Re-sending the whole thing now changes nothing.
        assert_equal 0 [r zadd zc {*}$cmd]
        assert_equal 140 [r zcard zc]
    }

    test "ZADD batch path - a converting ZADD survives a reload" {
        r del zc
        set seed {}
        for {set i 0} {$i < 20} {incr i} { lappend seed [expr {$i+0.25}] "c:$i" }
        r zadd zc {*}$seed
        set cmd $seed
        for {set i 20} {$i < 140} {incr i} { lappend cmd [expr {$i+0.25}] "c:$i" }
        r zadd zc {*}$cmd
        set before [r zrange zc 0 -1 WITHSCORES]
        r debug reload
        assert_encoding btree zc
        assert_equal $before [r zrange zc 0 -1 WITHSCORES]
    } {} {needs:debug}
}
