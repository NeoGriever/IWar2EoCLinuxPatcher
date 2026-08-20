// Measures the x86 time-stamp counter rate that I-War 2 reads at startup.
// The game stores this rate in a 32-bit value, so a rate above UINT32_MAX
// ticks per second needs its single-overflow compatibility repair.
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include <sched.h>
#include <time.h>

#if defined(__i386__) || defined(__x86_64__)
#include <x86intrin.h>
#else
#error "I-War 2's timing-counter check is only supported on x86 processors."
#endif

namespace {

constexpr std::uint64_t kOverflowThreshold = UINT32_MAX;

struct Sample {
    std::uint64_t ticks;
    std::uint64_t nanoseconds;
};

std::uint64_t monotonic_raw_nanoseconds() {
    timespec value{};
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &value) != 0) {
        std::fprintf(stderr, "clock_gettime(CLOCK_MONOTONIC_RAW): %s\n", std::strerror(errno));
        std::exit(2);
    }
    return static_cast<std::uint64_t>(value.tv_sec) * 1'000'000'000ULL + value.tv_nsec;
}

std::uint64_t read_tsc() {
    unsigned int auxiliary = 0;
    _mm_lfence();
    const std::uint64_t value = __rdtscp(&auxiliary);
    _mm_lfence();
    return value;
}

bool measure_sample(std::uint64_t requested_nanoseconds, Sample* result) {
    // A migration while sampling could combine unrelated per-CPU counters on
    // older or virtualized systems. Retry instead of reporting a false rate.
    for (int attempt = 0; attempt != 5; ++attempt) {
        const int start_cpu = sched_getcpu();
        const std::uint64_t start_time = monotonic_raw_nanoseconds();
        const std::uint64_t start_tsc = read_tsc();

        std::uint64_t end_time = start_time;
        while (end_time - start_time < requested_nanoseconds) {
            end_time = monotonic_raw_nanoseconds();
        }
        const std::uint64_t end_tsc = read_tsc();
        end_time = monotonic_raw_nanoseconds();
        const int end_cpu = sched_getcpu();

        if (start_cpu >= 0 && end_cpu >= 0 && start_cpu != end_cpu) {
            continue;
        }
        if (end_tsc <= start_tsc || end_time <= start_time) {
            continue;
        }
        result->ticks = end_tsc - start_tsc;
        result->nanoseconds = end_time - start_time;
        return true;
    }
    return false;
}

bool pin_to_current_cpu(cpu_set_t* previous_affinity) {
    if (sched_getaffinity(0, sizeof(*previous_affinity), previous_affinity) != 0) {
        return false;
    }
    const int cpu = sched_getcpu();
    if (cpu < 0) {
        return false;
    }
    cpu_set_t single_cpu{};
    CPU_ZERO(&single_cpu);
    CPU_SET(cpu, &single_cpu);
    return sched_setaffinity(0, sizeof(single_cpu), &single_cpu) == 0;
}

bool parse_positive(const char* value, std::uint64_t minimum, std::uint64_t maximum, std::uint64_t* parsed) {
    char* end = nullptr;
    errno = 0;
    const unsigned long long candidate = std::strtoull(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || candidate < minimum || candidate > maximum) {
        return false;
    }
    *parsed = candidate;
    return true;
}

void usage(const char* executable) {
    std::fprintf(stderr, "Usage: %s [--duration-ms 1000..10000] [--samples 1..9]\n", executable);
}

}  // namespace

int main(int argc, char** argv) {
    std::uint64_t duration_milliseconds = 1000;
    std::uint64_t sample_count = 3;
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--duration-ms") == 0 && index + 1 < argc) {
            if (!parse_positive(argv[++index], 100, 10'000, &duration_milliseconds)) {
                usage(argv[0]);
                return 64;
            }
        } else if (std::strcmp(argv[index], "--samples") == 0 && index + 1 < argc) {
            if (!parse_positive(argv[++index], 1, 9, &sample_count)) {
                usage(argv[0]);
                return 64;
            }
        } else {
            usage(argv[0]);
            return 64;
        }
    }

    const std::uint64_t requested_nanoseconds = duration_milliseconds * 1'000'000ULL;
    cpu_set_t original_affinity{};
    const bool affinity_pinned = pin_to_current_cpu(&original_affinity);
    std::vector<long double> rates;
    rates.reserve(sample_count);
    std::uint64_t measured_nanoseconds = 0;
    for (std::uint64_t index = 0; index < sample_count; ++index) {
        Sample sample{};
        if (!measure_sample(requested_nanoseconds, &sample)) {
            std::fprintf(stderr, "Unable to measure a stable time-stamp counter sample.\n");
            return 2;
        }
        measured_nanoseconds += sample.nanoseconds;
        rates.push_back(static_cast<long double>(sample.ticks) * 1'000'000'000.0L / sample.nanoseconds);
    }
    if (affinity_pinned && sched_setaffinity(0, sizeof(original_affinity), &original_affinity) != 0) {
        std::fprintf(stderr, "Unable to restore the original CPU affinity: %s\n", std::strerror(errno));
        return 2;
    }
    std::sort(rates.begin(), rates.end());
    const long double median_rate = rates[rates.size() / 2];
    const std::uint64_t tsc_hz = static_cast<std::uint64_t>(median_rate + 0.5L);

    std::printf("tsc_hz=%llu\n", static_cast<unsigned long long>(tsc_hz));
    std::printf("threshold_hz=%llu\n", static_cast<unsigned long long>(kOverflowThreshold));
    std::printf("samples=%llu\n", static_cast<unsigned long long>(sample_count));
    std::printf("measurement_ms=%llu\n", static_cast<unsigned long long>(measured_nanoseconds / 1'000'000ULL));
    std::printf("will_overflow_u32=%d\n", tsc_hz > kOverflowThreshold ? 1 : 0);
    return 0;
}
