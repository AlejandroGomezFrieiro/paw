//! The events that say which clips and lanes an edit added, changed or
//! removed.

use std::collections::HashMap;
use std::sync::Arc;

use crate::events::{Item, KernelEvent as E};
use crate::model::{Id, Track};

pub(super) type TrackIndex<'a> = HashMap<Id, &'a Arc<Track>>;

/// Where two states of a track's list of clips or lanes may differ: the
/// items of the state before and of the state after in that stretch.
pub(super) type Span<'a, T> = (Vec<&'a Arc<T>>, Vec<&'a Arc<T>>);

/// Report the clips or lanes that the touched tracks gained, lost or
/// changed, with the events `[added, changed, removed]` of their kind.
/// `id_of` gives an item's id and its stamp (a MIDI clip's notes).
pub(super) fn item_events<T>(
    [added_event, changed_event, removed_event]: [fn(Item) -> E; 3],
    (old, new): (&TrackIndex, &TrackIndex),
    touched: &dyn Fn(Id) -> bool,
    span: for<'a> fn(Option<&'a Track>, &'a Track) -> Span<'a, T>,
    id_of: fn(&T) -> (Id, Option<u64>),
    emit: &mut dyn FnMut(E),
) {
    let changed: Vec<(&Arc<Track>, Option<&&Arc<Track>>)> = new
        .values()
        .filter(|t| touched(t.id))
        .map(|t| (*t, old.get(&t.id)))
        .collect();
    // Each changed track against itself as it was: items in the same place
    // are found at once, and only what is left over (added, removed, or
    // moved from one track to another) is looked up by id.
    let mut added: Vec<(Id, Id, Option<u64>)> = Vec::new();
    let mut removed: Vec<(Id, (Id, Option<u64>))> = Vec::new();
    for (t, was) in &changed {
        let (before, after) = span(was.map(|w| &***w), t);
        let mut by_id = crate::model::ByKey::new(&before[..], |x: &&Arc<T>| id_of(x).0);
        let mut matched = vec![false; before.len()];
        for item in after {
            let (id, stamp) = id_of(item);
            match by_id.position(id) {
                Some(k) => {
                    matched[k] = true;
                    if !Arc::ptr_eq(before[k], item) {
                        emit(changed_event(Item { id, track: Some(t.id), stamp }));
                    }
                }
                None => added.push((id, t.id, stamp)),
            }
        }
        for (k, _) in matched.iter().enumerate().filter(|(_, m)| !**m) {
            let (id, stamp) = id_of(before[k]);
            removed.push((id, (t.id, stamp)));
        }
    }
    // Tracks that are gone take their items with them.
    for (id, t) in old.iter().filter(|(id, _)| !new.contains_key(id)) {
        removed.extend(span(None, t).1.into_iter().map(|item| {
            let (item, stamp) = id_of(item);
            (item, (*id, stamp))
        }));
    }
    let mut removed: HashMap<Id, (Id, Option<u64>)> = removed.into_iter().collect();
    for (id, track, stamp) in added {
        let event = if removed.remove(&id).is_some() { changed_event } else { added_event };
        emit(event(Item { id, track: Some(track), stamp }));
    }
    for (id, (track, stamp)) in removed {
        emit(removed_event(Item { id, track: Some(track), stamp }));
    }
}
