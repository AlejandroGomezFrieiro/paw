//! Property tests of the devices graph: its file form, and how it follows
//! the devices of its track.

use proptest::collection::vec;
use proptest::prelude::*;
use proptest::sample::Index;

use super::{Branch, Graph, Id, Node, Split, SplitKinds};
use crate::props::config;

/// The shape of a node: a device, or a split of a built-in kind with
/// branches of nodes.
#[derive(Clone, Debug)]
pub(crate) enum Shape {
    Device,
    Split(&'static str, Vec<Vec<Shape>>),
}

const KINDS: [&str; 7] = ["chain", "layer", "band", "ms", "lr", "key", "select"];

fn shape() -> impl Strategy<Value = Shape> {
    let leaf = Just(Shape::Device);
    leaf.prop_recursive(3, 24, 4, |inner| {
        prop_oneof![
            3 => Just(Shape::Device),
            1 => (0..KINDS.len(), vec(vec(inner, 0..3), 1..4)).prop_map(|(kind, branches)| Shape::Split(KINDS[kind], branches)),
        ]
    })
}

/// A graph of the nodes `top` in its root, with the devices from 1 and the
/// other ids from 1000. Each split gets as many branches as its kind takes.
pub(crate) fn build(top: &[Shape]) -> (Graph, Vec<Id>) {
    fn nodes(shapes: &[Shape], devices: &mut Vec<Id>, next: &mut Id) -> Vec<Node> {
        shapes.iter().map(|s| node(s, devices, next)).collect()
    }
    fn node(shape: &Shape, devices: &mut Vec<Id>, next: &mut Id) -> Node {
        match shape {
            Shape::Device => {
                let id = devices.len() as Id + 1;
                devices.push(id);
                Node::Device(id)
            }
            Shape::Split(kind, branches) => {
                let kinds = SplitKinds::default();
                let spec = kinds.spec(kind).expect("a built-in kind");
                let count = branches.len().clamp(spec.min, spec.max);
                let mut new_id = || {
                    *next += 1;
                    *next
                };
                let (word, values) = kinds.new_split_kind(kind, count).expect("a kind");
                let mut split = Split::new(word, values, count, &mut new_id);
                for (branch, shapes) in split.branches.iter_mut().zip(branches) {
                    branch.nodes = nodes(shapes, devices, next);
                }
                Node::Split(Box::new(split))
            }
        }
    }
    let (mut devices, mut next) = (Vec::new(), 1000);
    let top = nodes(top, &mut devices, &mut next);
    let mut new_id = || {
        next += 1;
        next
    };
    let mut graph = Graph::serial([], &mut new_id);
    graph.root.branches[0] = Branch { nodes: top, ..graph.root.branches[0].clone() };
    (graph, devices)
}

pub(crate) fn graph() -> impl Strategy<Value = (Graph, Vec<Id>)> {
    vec(shape(), 0..6).prop_map(|top| build(&top))
}

proptest! {
    #![proptest_config(config())]

    /// A graph written as its file has it and read again is the same graph.
    #[test]
    fn a_graph_written_and_read_again_is_the_same((graph, devices) in graph()) {
        prop_assert_eq!(graph.validate(&devices, &SplitKinds::default()), Ok(()));
        let text = serde_json::to_string(&graph).expect("a graph is written");
        let read: Graph = serde_json::from_str(&text).expect("a graph is read");
        prop_assert_eq!(read, graph);
    }

    /// After the devices of a track change in any way (some go, new ones
    /// come, in any place of the list), the graph fits them: it names each
    /// device of the track one time and passes its check, and the devices
    /// that stayed keep their order.
    #[test]
    fn a_graph_fits_any_change_of_its_devices(
        (mut graph, devices) in graph(),
        keep in vec(any::<bool>(), 32),
        added in vec(any::<Index>(), 0..4),
    ) {
        let kept: Vec<Id> = devices.iter().zip(keep.iter().cycle()).filter(|(_, k)| **k).map(|(d, _)| *d).collect();
        let mut now = kept.clone();
        for (n, at) in added.iter().enumerate() {
            now.insert(at.index(now.len() + 1), 500 + n as Id);
        }
        graph.fit(&now);
        prop_assert_eq!(graph.validate(&now, &SplitKinds::default()), Ok(()));
        let mut named = graph.devices();
        let stayed: Vec<Id> = named.iter().copied().filter(|id| kept.contains(id)).collect();
        prop_assert_eq!(stayed, kept, "the devices that stayed keep their order");
        named.sort_unstable();
        let mut want = now.clone();
        want.sort_unstable();
        prop_assert_eq!(named, want, "each device one time");
    }
}
