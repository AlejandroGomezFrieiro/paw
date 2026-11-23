//! A copy of what the engine plays, for someone listening on another
//! machine (`crate::monitor`).

use rtrb::Consumer;

use super::Session;

impl Session {
    /// Start copying what the engine plays into a queue with room for
    /// `seconds` of it; returns its reading end and the engine's sample
    /// rate. A new engine (after `engine_restart`) needs asking again.
    pub(crate) fn monitor_output(&mut self, seconds: f64) -> (Consumer<f32>, f64) {
        (self.engine.handle.monitor(seconds), self.engine.handle.sample_rate)
    }

    /// Stop copying it.
    pub(crate) fn stop_monitor(&mut self) {
        self.engine.handle.stop_monitor();
    }
}
