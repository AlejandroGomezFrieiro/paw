use serde_json::json;

use super::*;
use crate::model::kinds::Owner;

/// The device `n`.
fn d(n: u64) -> DeviceId {
    DeviceId::new(n)
}

/// An id source from `next` on.
fn ids(next: &mut u64) -> impl FnMut() -> NodeId + '_ {
    || {
        *next += 1;
        NodeId::new(*next)
    }
}

/// A split of `kind` with the branches `branches` (each a list of nodes),
/// and the ids that `next` gives.
fn split(kind: &str, branches: Vec<Vec<Node>>, next: &mut u64) -> Split {
    let (kind, values) = SplitKinds::builtin().new_split_kind(kind, branches.len()).expect("a kind");
    let mut s = Split::new(kind, values, branches.len(), &mut ids(next));
    for (branch, nodes) in s.branches.iter_mut().zip(branches) {
        branch.nodes = nodes;
    }
    s
}

fn device(n: u64) -> Node {
    Node::Device(d(n))
}

fn chain(nodes: Vec<Node>, next: &mut u64) -> Chain {
    Chain { root: split("chain", vec![nodes], next), taps: Vec::new() }
}

/// The devices 1 to 5.
const HELD: [DeviceId; 5] = [DeviceId::new(1), DeviceId::new(2), DeviceId::new(3), DeviceId::new(4), DeviceId::new(5)];

/// Check that the chain of the devices 1 to 5 gives `want`.
fn check(chain: &Chain, want: Result<(), &str>) {
    let got = chain.validate(&HELD, &SplitKinds::builtin()).map_err(|e| e.to_string());
    assert_eq!(got.as_ref().map(|_| ()).map_err(String::as_str), want, "{chain:?}");
}

#[test]
fn a_good_chain_passes() {
    let mut next = 100;
    let layer = split("layer", vec![vec![device(2)], vec![device(3)]], &mut next);
    let c = chain(vec![device(1), Node::Split(Box::new(layer)), device(4), device(5)], &mut next);
    check(&c, Ok(()));
}

#[test]
fn validate_refuses_each_bad_chain_with_its_message() {
    let mut next = 100;
    let tap = |device, from| Tap { device: d(device), from: Some(NodeId::new(from)) };
    let cases: Vec<(&str, Chain, &str)> = vec![
        (
            "a tap to a later node",
            Chain { taps: vec![tap(1, 3)], ..chain(vec![device(1), device(2), device(3)], &mut next) },
            "device 1 takes its key from node 3, which comes later in the signal",
        ),
        (
            "a tap to itself",
            Chain { taps: vec![tap(2, 2)], ..chain(vec![device(2)], &mut next) },
            "device 2 takes its key from node 2, which holds it: that is a loop",
        ),
        (
            "a mid/side split with three branches",
            chain(vec![Node::Split(Box::new(split("ms", vec![vec![], vec![], vec![]], &mut next)))], &mut next),
            "a ms split takes 2 to 2 branches, not 3",
        ),
        (
            "a band split with one band",
            chain(vec![Node::Split(Box::new(split("band", vec![vec![]], &mut next)))], &mut next),
            "a band split takes 2 to 6 branches, not 1",
        ),
        {
            let mut band = split("band", vec![vec![], vec![], vec![]], &mut next);
            band.values.insert("xover".into(), json!([2000.0, 120.0]));
            (
                "crossovers out of order",
                chain(vec![Node::Split(Box::new(band))], &mut next),
                "the crossovers of a band split go from low to high: 120 Hz comes after 2000 Hz",
            )
        },
        {
            let mut band = split("band", vec![vec![], vec![]], &mut next);
            band.values.insert("xover".into(), json!([120.0, 2000.0]));
            (
                "too many crossovers",
                chain(vec![Node::Split(Box::new(band))], &mut next),
                "a band split with 2 bands takes 1 crossovers, not 2",
            )
        },
        (
            "a device of another owner",
            chain(vec![device(9)], &mut next),
            "the chain names device 9, which its owner does not have",
        ),
        ("a device twice", chain(vec![device(1), device(1)], &mut next), "the id 1 is in the chain twice"),
    ];
    for (what, chain, message) in cases {
        let got = chain.validate(&HELD, &SplitKinds::builtin()).map_err(|e| e.to_string());
        assert_eq!(got, Err(message.to_owned()), "{what}");
    }
}

#[test]
fn a_tap_to_the_split_around_the_listener_is_a_loop() {
    let mut next = 100;
    let rack = split("chain", vec![vec![device(2)]], &mut next);
    let id = rack.id;
    let c = Chain { taps: vec![Tap { device: d(2), from: Some(id) }], ..chain(vec![Node::Split(Box::new(rack))], &mut next) };
    check(&c, Err(&format!("device 2 takes its key from node {id}, which holds it: that is a loop")));
}

#[test]
fn a_tap_to_a_node_that_ends_before_the_listener_passes() {
    let mut next = 100;
    let layer = split("layer", vec![vec![device(1)], vec![device(2)]], &mut next);
    let id = layer.id;
    let mut c = chain(vec![Node::Split(Box::new(layer)), device(3)], &mut next);
    // An earlier branch of the same split, the split before, the input.
    c.taps = vec![
        Tap { device: d(2), from: Some(NodeId::new(1)) },
        Tap { device: d(3), from: Some(id) },
        Tap { device: d(1), from: None },
    ];
    check(&c, Ok(()));
}

#[test]
fn an_extension_kind_takes_the_branches_it_defined_and_cannot_replace_a_kind_of_paw() {
    let mut kinds = SplitKinds::builtin();
    let ext = Owner::Extension("drums".into());
    kinds.define("drums.transient".parse().unwrap(), KindSpec { min: 2, max: 2, first: 2 }, ext.clone()).unwrap();
    let mut next = 100;
    let mut s = split("layer", vec![vec![device(1)], vec![]], &mut next);
    s.kind = "drums.transient".parse().unwrap();
    let c = chain(vec![Node::Split(Box::new(s))], &mut next);
    assert_eq!(c.validate(&[d(1)], &kinds), Ok(()));
    let refused = kinds.define("band".parse().unwrap(), KindSpec { min: 1, max: 2, first: 1 }, ext);
    assert_eq!(
        refused.map_err(|e| e.to_string()),
        Err("`band` is a kind of split of paw: an extension cannot define it again".to_owned())
    );
}

/// A split of a kind that no one has defined (an extension that is not
/// loaded) loads, passes the check of an edit, is named by `validate`, and
/// is written again as it was read.
#[test]
fn a_split_of_an_absent_kind_keeps_its_bytes_and_validate_names_it() {
    let text = r#"{"root":{"branches":[{"id":2,"nodes":[{"split":{"branches":[{"id":4,"nodes":[{"device":7}]},{"id":5,"nodes":[]}],"id":3,"kind":"drums.transient","values":{"attack":0.3}}}]}],"id":1,"kind":"chain"}}"#;
    let read: Chain = serde_json::from_str(text).expect("a chain of an absent kind loads");
    let kinds = SplitKinds::builtin();
    assert_eq!(read.check(&[d(7)], &kinds), Ok(()), "an edit may go on around it");
    assert_eq!(
        read.validate(&[d(7)], &kinds).map_err(|e| e.to_string()),
        Err("split 3 is of the kind `drums.transient`, which no loaded extension defines: load the extension that defines it".to_owned())
    );
    let written = serde_json::to_string(&serde_json::to_value(&read).unwrap()).unwrap();
    assert_eq!(written, text, "the same bytes");
}

#[test]
fn fit_drops_devices_that_went_and_puts_new_ones_after_the_node_before_them() {
    let mut next = 100;
    let layer = split("layer", vec![vec![device(2)], vec![device(3)]], &mut next);
    let mut c = chain(vec![device(1), Node::Split(Box::new(layer.clone())), device(4)], &mut next);
    // 4 went; 6 comes after 3 (inside the layer), 7 at the start.
    let now = [d(7), d(1), d(2), d(3), d(6)];
    assert!(c.fit(&now));
    assert_eq!(c.devices(), now);
    let top: Vec<NodeId> = c.root.branches[0].nodes.iter().map(Node::id).collect();
    assert_eq!(top, [NodeId::new(7), NodeId::new(1), layer.id, NodeId::new(6)], "a new device goes after the top node that holds the one before it");
    assert!(!c.fit(&now), "a chain that fits stays");
}
