/*!
  Copyright 2012, Mattias Holm
  mattias.holm(at)openorbit.org
 */

#ifndef DARWIN_POSIX_RT_EMU
#define DARWIN_POSIX_RT_EMU

#include <time.h>

/* iOS only gained clock_gettime in 10.0. Building against a modern SDK with
 * -miphoneos-version-min=6.0 still *declares* it, so it links as a weak import
 * and dyld resolves it to NULL on iOS 7 - the first call branches to address 0.
 * Guarding this polyfill on CLOCK_REALTIME (as it used to be) disables it
 * exactly when the modern SDK is in use, i.e. always. So: always define it. */
#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME		0
#define CLOCK_MONOTONIC		1
typedef int clockid_t;
#endif

int clock_gettime(clockid_t clock_id, struct timespec *ts);

#endif /*! DARWIN_POSIX_RT_EMU */
