/*
 * ios7_compat.c - symbols TDLib expects but iOS 7.1.2 does not have.
 *
 * Building against a modern SDK with -miphoneos-version-min=6.0 still declares
 * these, so they link as WEAK IMPORTS and dyld resolves them to NULL on iOS 7.
 * The first call then branches to address 0. That is exactly how the TDLib
 * probe died: a crash inside libtdjson.dylib with frame 0 at 0x00000000.
 *
 * Linked into libtdjson.dylib by scripts/build_tdlib_dylib.sh, where these
 * strong definitions win over the weak imports.
 */
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/clock.h>

/* clock_gettime: iOS 10.0. Mach clock services exist all the way back. */
int clock_gettime(clockid_t clock_id, struct timespec *ts)
{
	mach_timespec_t mts;
	static clock_serv_t rt_clock_serv;
	static clock_serv_t mono_clock_serv;

	switch ((int)clock_id) {
	case CLOCK_REALTIME:
		if (rt_clock_serv == 0)
			host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &rt_clock_serv);
		clock_get_time(rt_clock_serv, &mts);
		break;
	case CLOCK_MONOTONIC:
		if (mono_clock_serv == 0)
			host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &mono_clock_serv);
		clock_get_time(mono_clock_serv, &mts);
		break;
	default:
		errno = EINVAL;
		return -1;
	}

	ts->tv_sec = mts.tv_sec;
	ts->tv_nsec = mts.tv_nsec;
	return 0;
}

/* fdopendir: iOS 10.0. Recover the path from the descriptor and open that.
 * fdopendir takes ownership of fd, so close it once opendir succeeded. */
DIR *fdopendir(int fd)
{
	char path[PATH_MAX];
	DIR *d;

	if (fcntl(fd, F_GETPATH, path) == -1) {
		errno = EBADF;
		return NULL;
	}

	d = opendir(path);
	if (d)
		close(fd);
	return d;
}
