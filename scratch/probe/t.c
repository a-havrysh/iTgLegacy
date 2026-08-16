#include <stdio.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <unistd.h>
#include <mach/mach.h>
int main(void){
	int name[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
	struct kinfo_proc info; size_t len = sizeof(info);
	sysctl(name, 4, &info, &len, 0, 0);
	struct timeval now; gettimeofday(&now, 0);
	double ms = (now.tv_sec - info.kp_proc.p_starttime.tv_sec) * 1000.0 +
	            (now.tv_usec - info.kp_proc.p_starttime.tv_usec) / 1000.0;
	struct task_basic_info tb; mach_msg_type_number_t c = TASK_BASIC_INFO_COUNT;
	task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&tb, &c);
	printf("main at %.0f ms rss=%.2f MB\n", ms, tb.resident_size / 1048576.0);
	return 0;
}
