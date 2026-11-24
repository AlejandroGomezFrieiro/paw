//! The scheduling policy and priority of a thread, so that the threads that
//! help the audio thread (the workers of the pool, the audio thread of a
//! sandboxed plugin) run as it runs.
//!
//! Not `audio_thread_priority`: it asks RtKit over D-Bus (a C library for
//! the Nix build) and does not copy the policy and priority of the audio
//! thread. libc and not rustix: rustix has no wrapper for the pthread
//! scheduling calls (they act on a pthread, not on a kernel thread id).

/// A scheduling policy (`SCHED_OTHER`, `SCHED_FIFO`, ...) and its priority.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Scheduling {
    pub policy: i32,
    pub priority: i32,
}

impl Scheduling {
    /// The scheduling of an ordinary thread.
    #[cfg(unix)]
    pub const ORDINARY: Self = Self {
        policy: libc::SCHED_OTHER,
        priority: 0,
    };
    #[cfg(not(unix))]
    pub const ORDINARY: Self = Self {
        policy: 0,
        priority: 0,
    };

    /// Whether the policy is a real-time one.
    pub fn is_realtime(self) -> bool {
        #[cfg(unix)]
        return self.policy == libc::SCHED_FIFO || self.policy == libc::SCHED_RR;
        #[cfg(not(unix))]
        return false;
    }
}

/// The scheduling of the calling thread, without the flag that says its
/// children do not inherit it.
///
/// A thread that the system's helper (RtKit) made real-time carries
/// `SCHED_RESET_ON_FORK` in its policy. The flag is not a policy: another
/// thread that asks for the policy with the flag set gets an error, so each
/// reader of the policy clears it here.
#[cfg(unix)]
pub fn current() -> Scheduling {
    let mut policy = 0;
    // SAFETY: `sched_param` is a plain C struct of integers; all zeros is one.
    let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
    // SAFETY: the calling thread exists, and both out-pointers are to live
    // locals of the right types.
    let result = unsafe {
        libc::pthread_getschedparam(libc::pthread_self(), &raw mut policy, &raw mut param)
    };
    if result != 0 {
        return Scheduling::ORDINARY;
    }
    #[cfg(target_os = "linux")]
    let policy = policy & !libc::SCHED_RESET_ON_FORK;
    Scheduling {
        policy,
        priority: param.sched_priority,
    }
}

/// Give the calling thread a scheduling. Says whether the system took it: a
/// user without the right to run real-time gets `false`.
///
/// On Linux a real-time policy gets `SCHED_RESET_ON_FORK` again, which
/// [`current`] clears: a thread or a process that a plugin starts from its
/// audio thread then does not run real-time.
#[cfg(unix)]
pub fn set(scheduling: Scheduling) -> bool {
    #[cfg(target_os = "linux")]
    let policy = if scheduling.is_realtime() {
        scheduling.policy | libc::SCHED_RESET_ON_FORK
    } else {
        scheduling.policy
    };
    #[cfg(not(target_os = "linux"))]
    let policy = scheduling.policy;
    // SAFETY: `sched_param` is a plain C struct of integers; all zeros is one.
    let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
    param.sched_priority = scheduling.priority;
    // SAFETY: the calling thread exists, and `param` is a live local. A
    // policy or priority that the system does not take is an error, not UB.
    let result =
        unsafe { libc::pthread_setschedparam(libc::pthread_self(), policy, &raw const param) };
    result == 0
}

#[cfg(not(unix))]
pub fn current() -> Scheduling {
    Scheduling::ORDINARY
}

#[cfg(not(unix))]
pub fn set(_scheduling: Scheduling) -> bool {
    true
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;

    /// The children of a thread made real-time do not inherit its policy.
    #[test]
    fn a_real_time_thread_does_not_pass_its_policy_to_its_children() {
        let flags = std::thread::spawn(|| {
            let fifo = Scheduling {
                policy: libc::SCHED_FIFO,
                priority: 5,
            };
            if !set(fifo) {
                return None;
            }
            // SAFETY: 0 is the calling thread, which exists.
            let policy = unsafe { libc::sched_getscheduler(0) };
            Some((policy, current()))
        })
        .join()
        .unwrap();
        let Some((policy, now)) = flags else {
            eprintln!("skipped: this user may not make a thread real-time");
            return;
        };
        assert_eq!(policy, libc::SCHED_FIFO | libc::SCHED_RESET_ON_FORK);
        assert_eq!(
            now.policy,
            libc::SCHED_FIFO,
            "current gives the policy without the flag"
        );
    }
}
