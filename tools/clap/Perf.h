// A CPU diagnostic for the CLAP plugin, off unless the environment variable CMAJ_PLUGIN_PERF is set
// (setx CMAJ_PLUGIN_PERF 1, then restart the host). Every instance times its process calls and adds
// a line about every two seconds to <plugin name>-perf.log in the temp folder:
//
//   [instance] calls/s, frames per call, ms between calls, process time as a share of real time
//   (wall clock: the host's own CPU meter would say about this), the thread's CPU time as a share
//   (without the time it was preempted), the longest call, events per call, and whether the host
//   sends a transport.
//
// So the plugin's own account of what it costs can be set against a host's meter. No includes of
// its own: tools/clap-patch.mjs puts it after the wrapper's, with BRIDGE_PLUGIN_NAME defined.

#pragma once

namespace bridge::perf
{
    inline bool enabled()
    {
        static const bool on = std::getenv ("CMAJ_PLUGIN_PERF") != nullptr;
        return on;
    }

    inline double threadCpuSeconds()
    {
       #ifdef _WIN32
        FILETIME created, exited, kernel, user;

        if (GetThreadTimes (GetCurrentThread(), &created, &exited, &kernel, &user))
            return (static_cast<double> ((static_cast<uint64_t> (kernel.dwHighDateTime) << 32) | kernel.dwLowDateTime)
                    + static_cast<double> ((static_cast<uint64_t> (user.dwHighDateTime) << 32) | user.dwLowDateTime)) * 1.0e-7;
       #endif

        return 0.0;
    }

    struct Timer
    {
        using Clock = std::chrono::steady_clock;

        Clock::time_point windowStart {}, lastCall {};
        double busy = 0, longest = 0, gaps = 0, cpuStart = 0;
        uint64_t calls = 0, frames = 0, events = 0, transports = 0;
        int id = 0;

        template <typename Process>
        clap_process_status run (const clap_process_t* process, Process&& fn)
        {
            const auto start = Clock::now();

            if (calls == 0 && windowStart == Clock::time_point{})
            {
                windowStart = start;
                cpuStart = threadCpuSeconds();
            }
            else if (lastCall != Clock::time_point{})
            {
                gaps += std::chrono::duration<double> (start - lastCall).count();
            }

            const auto status = fn();
            const auto end = Clock::now();
            const auto took = std::chrono::duration<double> (end - start).count();

            busy += took;
            longest = std::max (longest, took);
            ++calls;
            frames += process->frames_count;
            events += process->in_events != nullptr ? process->in_events->size (process->in_events) : 0;
            transports += process->transport != nullptr ? 1 : 0;
            lastCall = end;

            const auto window = std::chrono::duration<double> (end - windowStart).count();

            if (window >= 2.0)
            {
                const auto cpu = threadCpuSeconds() - cpuStart;
                static std::mutex lock;
                std::lock_guard<std::mutex> hold (lock);
                std::ofstream log (std::filesystem::temp_directory_path() / (std::string (BRIDGE_PLUGIN_NAME) + "-perf.log"), std::ios::app);
                char line[400];
                std::snprintf (line, sizeof (line),
                               "[%d] %.0f calls/s, %.0f frames, %.2f ms apart, process %.2f%% of real time, thread cpu %.2f%%, longest %.2f ms, %.1f events/call, transport %s\n",
                               id, static_cast<double> (calls) / window, static_cast<double> (frames) / static_cast<double> (calls),
                               1000.0 * gaps / static_cast<double> (calls), 100.0 * busy / window, 100.0 * cpu / window,
                               1000.0 * longest, static_cast<double> (events) / static_cast<double> (calls),
                               transports != 0 ? "yes" : "no");
                log << line;

                windowStart = end;
                cpuStart += cpu;
                busy = longest = gaps = 0;
                calls = frames = events = transports = 0;
            }

            return status;
        }
    };

    /// The timer of the instance with this address.
    inline Timer& timerFor (const void* instance)
    {
        static std::mutex lock;
        static std::unordered_map<const void*, std::unique_ptr<Timer>> timers;
        std::lock_guard<std::mutex> hold (lock);
        auto& timer = timers[instance];

        if (! timer)
        {
            timer = std::make_unique<Timer>();
            timer->id = static_cast<int> (timers.size());
        }

        return *timer;
    }
}
