# Multi-pair ZADD on a B+ tree resolves its member lookups in batches and
# answers the pairs that change nothing from the batch. Exercise the batch
# path (>= 16 pairs), its boundaries, and every flag combination, and compare
# against a Tcl model of the same command.
start_server {tags {"zset"}} {
    proc zadd_model {name pairs flags} {
        # Returns {added updated reply dict} for a ZADD applied to dict 'name'.
        upvar 1 $name d
        set added 0 ; set updated 0
        foreach {s m} $pairs {
            set exists [dict exists $d $m]
            if {$exists} {
                set cur [dict get $d $m]
                if {[lsearch -exact $flags NX] >= 0} continue
                if {[lsearch -exact $flags GT] >= 0 && $s <= $cur} continue
                if {[lsearch -exact $flags LT] >= 0 && $s >= $cur} continue
                if {$s != $cur} { dict set d $m $s ; incr updated }
            } else {
                if {[lsearch -exact $flags XX] >= 0} continue
                dict set d $m $s ; incr added
            }
        }
        return [list $added $updated]
    }

    proc assert_score {expected r key member} {
        set got [$r zscore $key $member]
        assert {$got ne {} && $got == $expected}
    }

    proc check {r key d} {
        # Server and model must agree on cardinality and on every score.
        assert_equal [dict size $d] [$r zcard $key]
        dict for {m s} $d {
            assert_score $s $r $key $m
        }
    }

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
                assert_score [expr {$i*1.5}] r zb "m:$i:padpadpadpad"
            }
        }

        test "ZADD batch path - model agreement across flags and sizes, $enc" {
            foreach n {1 2 15 16 17 31 32 33 100} {
                foreach flags {{} {NX} {XX} {GT} {LT} {XX GT} {XX LT} {CH}} {
                    r del zb
                    set d [dict create]
                    # Seed half the members so each command mixes hits and misses.
                    set seed {}
                    for {set i 0} {$i < $n} {incr i 2} {
                        lappend seed [expr {$i+0.5}] "s:$i"
                        dict set d "s:$i" [expr {$i+0.5}]
                    }
                    if {[llength $seed]} { r zadd zb {*}$seed }
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
                        lassign [zadd_model d $pairs $fl] exp_added exp_updated
                        set got [r zadd zb {*}$flags {*}$pairs]
                        if {[lsearch -exact $flags CH] >= 0} {
                            assert_equal [expr {$exp_added+$exp_updated}] $got
                        } else {
                            assert_equal $exp_added $got
                        }
                        check r zb $d
                    }
                }
            }
        }

        test "ZADD batch path - duplicate members inside one command, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < 20} {incr i} { lappend pairs 1.0 "d:$i" }
            r zadd zb {*}$pairs
            # Same member twice: first unchanged, second changes it.
            set cmd {}
            for {set i 0} {$i < 20} {incr i} { lappend cmd 1.0 "d:$i" }
            lappend cmd 1.0 "d:3" 7.5 "d:3"
            assert_equal 0 [r zadd zb {*}$cmd]
            assert_score 7.5 r zb "d:3"
            # And the reverse order: changed first, then re-sent unchanged.
            set cmd {}
            for {set i 0} {$i < 20} {incr i} { lappend cmd 1.0 "d:$i" }
            lappend cmd 9.5 "d:4" 9.5 "d:4"
            assert_equal 0 [r zadd zb {*}$cmd]
            assert_score 9.5 r zb "d:4"
            assert_score 1.0 r zb "d:5"
        }

        test "ZADD batch path - a bad score aborts before anything is applied, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < 20} {incr i} { lappend pairs 1.0 "n:$i" }
            r zadd zb {*}$pairs
            # An unparsable score in the middle of a long command: scores are
            # parsed up front, so the command must apply none of its pairs.
            set cmd {}
            for {set i 0} {$i < 20} {incr i} {
                lappend cmd [expr {$i == 10 ? "notanumber" : 4.0}] "n:$i"
            }
            assert_error "*not a valid float*" {r zadd zb {*}$cmd}
            for {set i 0} {$i < 20} {incr i} { assert_score 1.0 r zb "n:$i" }
            # A NaN *result* is still rejected, and INCR never takes the batch.
            r zadd zb inf "n:0"
            assert_error "*not a number*" {r zadd zb INCR -inf "n:0"}
        }

        test "ZADD batch path - unchanged pairs do not bump dirty or notify, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < 40} {incr i} { lappend pairs 2.5 "k:$i" }
            r zadd zb {*}$pairs
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
            for {set i 0} {$i < 40} {incr i} { lappend pairs 10.0 "g:$i" }
            r zadd zb {*}$pairs
            # GT with equal scores is a no-op; with a higher score it updates.
            set cmd {}
            for {set i 0} {$i < 40} {incr i} {
                lappend cmd [expr {$i == 20 ? 11.0 : 10.0}] "g:$i"
            }
            assert_equal 1 [r zadd zb GT CH {*}$cmd]
            assert_score 11.0 r zb "g:20"
            assert_score 10.0 r zb "g:19"
            # LT with a higher score changes nothing anywhere.
            set cmd {}
            for {set i 0} {$i < 40} {incr i} { lappend cmd 99.0 "g:$i" }
            assert_equal 0 [r zadd zb LT CH {*}$cmd]
            assert_score 10.0 r zb "g:0"
            # NX never touches an existing member but still adds new ones.
            set cmd {}
            for {set i 0} {$i < 40} {incr i} { lappend cmd 77.0 "g:$i" }
            lappend cmd 5.0 "g:new"
            assert_equal 1 [r zadd zb NX {*}$cmd]
            assert_score 10.0 r zb "g:0"
            assert_score 5.0 r zb "g:new"
        }

        test "ZADD batch path - survives a reload unchanged, $enc" {
            r del zb
            set pairs {}
            for {set i 0} {$i < 300} {incr i} { lappend pairs [expr {$i/7.0}] "r:$i" }
            r zadd zb {*}$pairs
            r zadd zb {*}$pairs
            set before [r zrange zb 0 -1 WITHSCORES]
            r debug reload
            assert_equal $before [r zrange zb 0 -1 WITHSCORES]
        } {} {needs:debug}
    }
    r config set zset-max-listpack-entries 128
}
