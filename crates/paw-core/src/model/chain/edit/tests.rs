//! The edits of a chain: property tests over any chain of `chain/props.rs`,
//! and the refusals.

use proptest::prelude::*;
use proptest::sample::Index;

use super::*;
use crate::model::chain::props::{Shape, build, chain};
use crate::model::chain::SplitKinds;
use crate::props::config;

/// Each node of the chain in its place: its branch, its index there and
/// its id, in signal order.
fn places(chain: &Chain) -> Vec<(NodeId, usize, NodeId)> {
    let mut out = Vec::new();
    chain.root.each_split(&mut |split| {
        for branch in &split.branches {
            out.extend(branch.nodes.iter().enumerate().map(|(at, n)| (branch.id, at, n.id())));
        }
    });
    out
}

/// Each branch of the chain.
fn branches(chain: &Chain) -> Vec<NodeId> {
    let mut out = Vec::new();
    chain.root.each_split(&mut |split| out.extend(split.branches.iter().map(|b| b.id)));
    out
}

/// A layer split with ids from 5000, as a session makes it for a wrap.
fn layer() -> Split {
    let mut next = 5000;
    let (kind, values) = SplitKinds::builtin().new_split_kind("layer", 2).expect("a kind");
    Split::new(kind, values, 2, &mut || {
        next += 1;
        NodeId::new(next)
    })
}

fn ok(chain: &Chain, devices: &[DeviceId]) -> Result<(), ChainError> {
    chain.check(devices, &SplitKinds::builtin())
}

proptest! {
    #![proptest_config(config())]

    /// A wrap of any row of nodes of one branch gives a chain that passes
    /// its check with the devices in the same signal order, and an unwrap
    /// of the new split gives the chain before the wrap.
    #[test]
    fn a_wrap_then_an_unwrap_gives_the_chain_back(
        (before, devices) in chain(),
        which in any::<Index>(),
        start in any::<Index>(),
        len in any::<Index>(),
    ) {
        let rows: Vec<(NodeId, Vec<NodeId>)> = branches(&before)
            .into_iter()
            .map(|b| (b, before.root.branch(b).expect("a branch").nodes.iter().map(Node::id).collect::<Vec<_>>()))
            .filter(|(_, nodes)| !nodes.is_empty())
            .collect();
        prop_assume!(!rows.is_empty());
        let (_, nodes) = &rows[which.index(rows.len())];
        let from = start.index(nodes.len());
        let row = &nodes[from..from + 1 + len.index(nodes.len() - from)];
        let split = layer();
        let id = split.id;
        let wrapped = wrap(&before, row, split).expect("a row of one branch wraps");
        prop_assert_eq!(ok(&wrapped, &devices), Ok(()));
        prop_assert_eq!(wrapped.devices(), before.devices(), "the signal order stays");
        let back = unwrap(&wrapped, id, None).expect("the new split unwraps");
        prop_assert_eq!(back, before);
    }

    /// A move of any node to any place is refused only when a split would
    /// go into itself; else the chain passes its check, has the same
    /// devices, and the node is at the place.
    #[test]
    fn a_move_puts_the_node_at_its_place_and_keeps_the_devices(
        (before, devices) in chain(),
        which in any::<Index>(),
        target in any::<Index>(),
        how in 0..3usize,
        index in 0..4usize,
    ) {
        let nodes = places(&before);
        prop_assume!(!nodes.is_empty());
        let (_, _, id) = nodes[which.index(nodes.len())];
        let place = match how {
            0 => Place::Before(nodes[target.index(nodes.len())].2),
            1 => Place::After(nodes[target.index(nodes.len())].2),
            _ => {
                let all = branches(&before);
                Place::Into { branch: all[target.index(all.len())], index }
            }
        };
        prop_assume!(place.near() != id);
        let inside = |n: NodeId| before.root.split(id).is_some_and(|s| !s.path_to(n).is_empty());
        match move_node(&before, id, place) {
            Err(ChainError::IntoItself) => prop_assert!(inside(place.near())),
            Err(other) => prop_assert!(false, "refused: {other}"),
            Ok(after) => {
                prop_assert!(!inside(place.near()));
                prop_assert_eq!(ok(&after, &devices), Ok(()));
                let mut was = before.devices();
                let mut now = after.devices();
                was.sort_unstable();
                now.sort_unstable();
                prop_assert_eq!(now, was, "the same devices");
                let (branch, at) = after.root.place_of(id).expect("the node is in the chain");
                match place {
                    Place::Before(t) => prop_assert_eq!(after.root.place_of(t), Some((branch, at + 1))),
                    Place::After(t) => prop_assert_eq!(after.root.place_of(t).map(|(b, i)| (b, i + 1)), Some((branch, at))),
                    Place::Into { branch: b, index } => {
                        prop_assert_eq!(branch, b);
                        prop_assert!(at <= index);
                    }
                }
            }
        }
    }

    /// A remove of any node takes exactly the devices it held, and the
    /// others keep their signal order.
    #[test]
    fn a_remove_takes_the_devices_of_the_node((before, _) in chain(), which in any::<Index>()) {
        let nodes = places(&before);
        prop_assume!(!nodes.is_empty());
        let (_, _, id) = nodes[which.index(nodes.len())];
        let held = match before.root.split(id) {
            Some(split) => split.devices(),
            None => vec![DeviceId::from(id)],
        };
        let after = remove(&before, id).expect("a node is removed");
        let rest: Vec<DeviceId> = before.devices().into_iter().filter(|d| !held.contains(d)).collect();
        prop_assert_eq!(after.devices(), rest.clone());
        prop_assert_eq!(ok(&after, &rest), Ok(()));
    }

    /// A change of a value of any branch changes that value only.
    #[test]
    fn a_set_changes_one_value((before, _) in chain(), which in any::<Index>(), gain in -120.0..24.0f64) {
        let all = branches(&before);
        let id = all[which.index(all.len())];
        let after = set(&before, id, Change::Gain(gain)).expect("a branch has a gain");
        let mut want = before.clone();
        want.root.branch_mut(id).expect("the branch").gain = gain;
        prop_assert_eq!(after, want);
    }
}

#[test]
fn each_refused_edit_says_why() {
    let (c, _) = build(&[Shape::Device, Shape::Split("layer", vec![vec![Shape::Device], vec![]]), Shape::Device]);
    let top: Vec<NodeId> = c.root.branches[0].nodes.iter().map(Node::id).collect();
    let (first, layer_id, last) = (top[0], top[1], top[2]);
    let inner = c.root.split(layer_id).unwrap().branches[0].id;
    let root = c.root.id;
    let cases: Vec<(Result<Chain, ChainError>, String)> = vec![
        (wrap(&c, &[], layer()), "nothing to wrap".into()),
        (wrap(&c, &[first, last], layer()), "the nodes to wrap are not in a row".into()),
        (wrap(&c, &[first, DeviceId::new(2).into()], layer()), "the nodes to wrap are not in one branch".into()),
        (unwrap(&c, root, None), "the root of the chain cannot be unwrapped".into()),
        (unwrap(&c, layer_id, Some(first)), format!("branch {first} is not a branch of split {layer_id}")),
        (move_node(&c, root, Place::Before(first)), "the root of the chain cannot be moved".into()),
        (move_node(&c, layer_id, Place::Into { branch: inner, index: 0 }), "a split cannot move into itself".into()),
        (move_node(&c, first, Place::Before(NodeId::new(77))), "no node 77 in the chain".into()),
        (remove(&c, root), "the root of the chain cannot be removed".into()),
        (set(&c, layer_id, Change::Pan(0.5)), "a split has no value `pan`: say name, mix, gain, kind or values".into()),
        (set(&c, inner, Change::Mix(0.5)), "a branch has no value `mix`: say name, gain, pan, mute, solo or zone".into()),
        (add_macro(&c, first, Macro { id: NodeId::new(90), name: "m".into(), value: 0.0 }), format!("{first} is not a split")),
        (link(&c, first, DeviceId::new(1), "gain".into(), Some(0.5)), format!("{first} is not a macro")),
    ];
    for (result, message) in cases {
        assert_eq!(result.map(drop).map_err(|e| e.to_string()), Err(message));
    }
}

#[test]
fn a_band_split_keeps_one_crossover_fewer_than_its_bands() {
    let (c, _) = build(&[Shape::Split("band", vec![vec![], vec![], vec![]])]);
    let band = c.root.branches[0].nodes[0].id();
    let more = add_branch(&c, band, Branch::new(NodeId::new(900)), None).unwrap();
    assert_eq!(more.root.split(band).unwrap().values["xover"], serde_json::json!([120.0, 800.0, 4000.0]));
    let fewer = remove(&more, NodeId::new(900)).unwrap();
    assert_eq!(fewer.root.split(band).unwrap().values["xover"], serde_json::json!([120.0, 2000.0]));
}
