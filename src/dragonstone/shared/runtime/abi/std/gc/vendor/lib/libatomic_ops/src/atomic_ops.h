#ifndef AO_ATOMIC_OPS_H
#define AO_ATOMIC_OPS_H

#if defined(_MSC_VER) || defined(__MINGW32__)
  #include <intrin.h>
  #include <windows.h>

  #ifdef _WIN64
    typedef volatile __int64 AO_t;
  #else
    typedef volatile LONG AO_t;
  #endif
  typedef unsigned char AO_TS_t;

  #define AO_TS_CLEAR 0
  #define AO_TS_SET 1
  #define AO_TS_INITIALIZER AO_TS_CLEAR

  #define AO_compiler_barrier() _ReadWriteBarrier()

  #define AO_HAVE_nop_full
  static inline void AO_nop_full(void) {
    MemoryBarrier();
  }

  #define AO_HAVE_load
  static inline AO_t AO_load(const volatile AO_t *addr) {
    return *addr;
  }

  #define AO_HAVE_store
  static inline void AO_store(volatile AO_t *addr, AO_t val) {
    *addr = val;
  }

  #define AO_HAVE_test_and_set_full
  static inline AO_TS_t AO_test_and_set_full(volatile AO_TS_t *addr) {
    return (AO_TS_t)_InterlockedExchange8((char*)addr, AO_TS_SET);
  }

  #define AO_HAVE_fetch_and_add
  static inline AO_t AO_fetch_and_add(volatile AO_t *addr, AO_t incr) {
    #ifdef _WIN64
      return _InterlockedExchangeAdd64((__int64*)addr, incr);
    #else
      return _InterlockedExchangeAdd((LONG*)addr, incr);
    #endif
  }

  #define AO_HAVE_fetch_and_add1
  static inline AO_t AO_fetch_and_add1(volatile AO_t *addr) {
    #ifdef _WIN64
      return _InterlockedIncrement64((__int64*)addr) - 1;
    #else
      return _InterlockedIncrement((LONG*)addr) - 1;
    #endif
  }

  #define AO_HAVE_compare_and_swap
  static inline int AO_compare_and_swap(volatile AO_t *addr, AO_t old_val, AO_t new_val) {
    #ifdef _WIN64
      return _InterlockedCompareExchange64((__int64*)addr, new_val, old_val) == old_val;
    #else
      return _InterlockedCompareExchange((LONG*)addr, new_val, old_val) == old_val;
    #endif
  }

  #define AO_HAVE_or
  static inline void AO_or(volatile AO_t *addr, AO_t val) {
    #ifdef _WIN64
      _InterlockedOr64((__int64*)addr, val);
    #else
      _InterlockedOr((LONG*)addr, val);
    #endif
  }

  #define AO_HAVE_load_acquire
  static inline AO_t AO_load_acquire(const volatile AO_t *addr) {
    AO_t result = *addr;
    MemoryBarrier();
    return result;
  }

  #define AO_HAVE_store_release
  static inline void AO_store_release(volatile AO_t *addr, AO_t val) {
    MemoryBarrier();
    *addr = val;
  }

  #define AO_HAVE_char_load
  static inline unsigned char AO_char_load(const volatile unsigned char *addr) {
    return *addr;
  }

  #define AO_HAVE_char_store
  static inline void AO_char_store(volatile unsigned char *addr, unsigned char val) {
    *addr = val;
  }
#endif

#endif
