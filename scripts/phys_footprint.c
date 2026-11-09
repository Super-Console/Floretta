/* Darwin-only sampler. scripts/measure-open-rss.sh compiles this on macOS.
   Prints task_info TASK_VM_INFO phys_footprint in bytes. */
#include <stdint.h>
#include <stdio.h>
#include <mach/mach.h>

int main(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "task_info phys_footprint failed: %d\n", kr);
        return 1;
    }
    if (info.phys_footprint == 0) {
        fprintf(stderr, "phys_footprint was 0\n");
        return 1;
    }
    printf("%llu\n", (unsigned long long)info.phys_footprint);
    return 0;
}
