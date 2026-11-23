//! The values of automation and state lanes along the song: points in
//! beats, read between them.

/// The value of a lane at `beat`: linear between points, the first value
/// before the first point and the last after the last. `points` must be sorted
/// by beat; where two share a beat, the later one wins from that beat on.
pub fn value_at(points: &[(f64, f64)], beat: f64) -> Option<f64> {
    let next = points.partition_point(|p| p.0 <= beat);
    match (next.checked_sub(1).map(|i| points[i]), points.get(next)) {
        (None, None) => None,
        (Some(a), None) => Some(a.1),
        (None, Some(b)) => Some(b.1),
        (Some(a), Some(b)) => Some(a.1 + (b.1 - a.1) * (beat - a.0) / (b.0 - a.0)),
    }
}

/// The index of the state in force at `beat`: that of the last point at
/// or before it, the first point's before the first. None with no points.
pub fn state_at(points: &[(f64, u32)], beat: f64) -> Option<u32> {
    let next = points.partition_point(|p| p.0 <= beat);
    match next.checked_sub(1) {
        Some(i) => Some(points[i].1),
        None => points.first().map(|p| p.1),
    }
}

/// The beat of the first point after `beat`, if any.
pub fn next_point(points: &[(f64, u32)], beat: f64) -> Option<f64> {
    let next = points.partition_point(|p| p.0 <= beat);
    points.get(next).map(|p| p.0)
}

#[cfg(test)]
mod tests {
    use super::{next_point, state_at, value_at};

    #[test]
    fn states_hold_to_the_next_point() {
        let points = [(4.0, 1), (8.0, 0), (8.0, 2)];
        assert_eq!(state_at(&[], 1.0), None);
        assert_eq!(
            state_at(&points, 0.0),
            Some(1),
            "the first state before the first point"
        );
        assert_eq!(state_at(&points, 4.0), Some(1));
        assert_eq!(state_at(&points, 7.99), Some(1));
        assert_eq!(
            state_at(&points, 8.0),
            Some(2),
            "the later of two on one beat"
        );
        assert_eq!(next_point(&points, 4.0), Some(8.0));
        assert_eq!(next_point(&points, 3.0), Some(4.0));
        assert_eq!(next_point(&points, 8.0), None);
    }

    #[test]
    fn interpolates_and_holds() {
        let points = [(2.0, -60.0), (6.0, 0.0), (6.0, -12.0)];
        assert_eq!(value_at(&[], 1.0), None);
        assert_eq!(value_at(&points, 0.0), Some(-60.0));
        assert_eq!(value_at(&points, 4.0), Some(-30.0));
        assert_eq!(value_at(&points, 6.0), Some(-12.0));
        assert_eq!(value_at(&points, 100.0), Some(-12.0));
    }
}
