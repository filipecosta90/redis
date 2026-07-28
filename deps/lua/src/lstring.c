/*
** $Id: lstring.c,v 2.8.1.1 2007/12/27 13:02:25 roberto Exp $
** String table (keeps all strings handled by Lua)
** See Copyright Notice in lua.h
*/


#include <string.h>

#define lstring_c
#define LUA_CORE

#include "lua.h"

#include "lmem.h"
#include "lobject.h"
#include "lstate.h"
#include "lstring.h"



void luaS_resize (lua_State *L, int newsize) {
  GCObject **newhash;
  stringtable *tb;
  int i;
  if (G(L)->gcstate == GCSsweepstring)
    return;  /* cannot resize during GC traverse */
  newhash = luaM_newvector(L, newsize, GCObject *);
  tb = &G(L)->strt;
  for (i=0; i<newsize; i++) newhash[i] = NULL;
  /* rehash */
  for (i=0; i<tb->size; i++) {
    GCObject *p = tb->hash[i];
    while (p) {  /* for each node in the list */
      GCObject *next = p->gch.next;  /* save next */
      unsigned int h = gco2ts(p)->hash;
      int h1 = lmod(h, newsize);  /* new position */
      lua_assert(cast_int(h%newsize) == lmod(h, newsize));
      p->gch.next = newhash[h1];  /* chain it */
      newhash[h1] = p;
      p = next;
    }
  }
  luaM_freearray(L, tb->hash, tb->size, TString *);
  tb->size = newsize;
  tb->hash = newhash;
}


static TString *newlstr (lua_State *L, const char *str, size_t l,
                                       unsigned int h) {
  TString *ts;
  stringtable *tb;
  if (l+1 > (MAX_SIZET - sizeof(TString))/sizeof(char))
    luaM_toobig(L);
  ts = cast(TString *, luaM_malloc(L, (l+1)*sizeof(char)+sizeof(TString)));
  ts->tsv.len = l;
  ts->tsv.hash = h;
  ts->tsv.marked = luaC_white(G(L));
  ts->tsv.tt = LUA_TSTRING;
  ts->tsv.reserved = 0;
  memcpy(ts+1, str, l*sizeof(char));
  ((char *)(ts+1))[l] = '\0';  /* ending 0 */
  tb = &G(L)->strt;
  h = lmod(h, tb->size);
  ts->tsv.next = tb->hash[h];  /* chain new entry */
  tb->hash[h] = obj2gco(ts);
  tb->nuse++;
  if (tb->nuse > cast(lu_int32, tb->size) && tb->size <= MAX_INT/2)
    luaS_resize(L, tb->size*2);  /* too crowded */
  return ts;
}


TString *luaS_newlstr (lua_State *L, const char *str, size_t l) {
  GCObject *o;
  /* MurmurHash3_x86_32-style mixer: 4-byte blocks with high ILP.
     Preserves interning semantics (memcmp below guarantees correctness);
     hash is per-process (intern table only), so distribution can change. */
  unsigned int h;
  {
    const unsigned int c1 = 0xcc9e2d51u;
    const unsigned int c2 = 0x1b873593u;
    unsigned int h32 = cast(unsigned int, l);  /* seed */
    size_t nblocks = l >> 2;
    size_t i;
    for (i = 0; i < nblocks; i++) {
      unsigned int k;
      memcpy(&k, str + (i << 2), 4);
      k *= c1;
      k = (k << 15) | (k >> 17);
      k *= c2;
      h32 ^= k;
      h32 = (h32 << 13) | (h32 >> 19);
      h32 = h32 * 5u + 0xe6546b64u;
    }
    {
      const unsigned char *tail = (const unsigned char *)(str + (nblocks << 2));
      unsigned int k = 0;
      size_t rem = l & 3u;
      if (rem >= 3) k ^= (unsigned int)tail[2] << 16;
      if (rem >= 2) k ^= (unsigned int)tail[1] << 8;
      if (rem >= 1) {
        k ^= (unsigned int)tail[0];
        k *= c1;
        k = (k << 15) | (k >> 17);
        k *= c2;
        h32 ^= k;
      }
    }
    h32 ^= (unsigned int)l;
    h32 ^= h32 >> 16;
    h32 *= 0x85ebca6bu;
    h32 ^= h32 >> 13;
    h32 *= 0xc2b2ae35u;
    h32 ^= h32 >> 16;
    h = h32;
  }
  for (o = G(L)->strt.hash[lmod(h, G(L)->strt.size)];
       o != NULL;
       o = o->gch.next) {
    TString *ts = rawgco2ts(o);
    if (ts->tsv.len == l && (memcmp(str, getstr(ts), l) == 0)) {
      /* string may be dead */
      if (isdead(G(L), o)) changewhite(o);
      return ts;
    }
  }
  return newlstr(L, str, l, h);  /* not found */
}


Udata *luaS_newudata (lua_State *L, size_t s, Table *e) {
  Udata *u;
  if (s > MAX_SIZET - sizeof(Udata))
    luaM_toobig(L);
  u = cast(Udata *, luaM_malloc(L, s + sizeof(Udata)));
  u->uv.marked = luaC_white(G(L));  /* is not finalized */
  u->uv.tt = LUA_TUSERDATA;
  u->uv.len = s;
  u->uv.metatable = NULL;
  u->uv.env = e;
  /* chain it on udata list (after main thread) */
  u->uv.next = G(L)->mainthread->next;
  G(L)->mainthread->next = obj2gco(u);
  return u;
}

