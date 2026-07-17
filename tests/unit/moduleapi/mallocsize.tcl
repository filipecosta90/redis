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

    test {MEMORY USAGE accounts for the moduleValue wrapper} {
        # Regression test: kvobjComputeSize() must include sizeof(moduleValue)
        # for OBJ_MODULE keys. The 16-byte wrapper (moduleType* + value*) is
        # allocated by createModuleObject() and never included in either
        # zmalloc_size(o) or moduleGetMemUsage(). Before the fix MU under-
        # reports by 16 B/key. The two lower bounds below fail on the pre-fix
        # binary (MU = 64 for len=8, 88 for len=40) and pass on the fix
        # (MU = 80 / 104).
        r del smallkey
        r del bigkey
        assert_equal [r mallocsize.setraw smallkey 8] {OK}
        assert_morethan [r memory usage smallkey] 72
        assert_equal [r mallocsize.setraw bigkey 40] {OK}
        assert_morethan [r memory usage bigkey] 96
        # Wrapper contribution is a fixed 16 B — independent of the payload,
        # so both keys must exceed a floor that includes it.
    }
}
