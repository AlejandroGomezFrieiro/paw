//! Property tests of the chain: its file form, and how it follows the
//! devices of its owner. `chain/edit/tests.rs` uses its strategy.

use proptest::collection::vec;
use proptest::prelude::*;
use proptest::sample::Index;

use super::{Branch, Chain, Node, Split, SplitKinds};
use crate::model::ids::{DeviceId, NodeId};
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

/// A chain of the nodes `top` in its root, with the devices from 1 and the
/// other ids from 1000. Each split gets as many branches as its kind takes.
pub(crate) fn build(top: &[Shape]) -> (Chain, Vec<DeviceId>) {
    fn nodes(shapes: &[Shape], devices: &mut Vec<DeviceId>, next: &mut u64) -> Vec<Node> {
        shapes.iter().map(|s| node(s, devices, next)).collect()
    }
    fn node(shape: &Shape, devices: &mut Vec<DeviceId>, next: &mut u64) -> Node {
        match shape {
            Shape::Device => {
                let id = DeviceId::new(devices.len() as u64 + 1);
                devices.push(id);
                Node::Device(id)
            }
            Shape::Split(kind, branches) => {
                let kinds = SplitKinds::builtin();
                let spec = kinds.get(&kind.parse().expect("a kind name")).expect("a built-in kind").spec();
                let count = branches.len().clamp(spec.min, spec.max);
                let mut new_id = || {
                    *next += 1;
                    NodeId::new(*next)
                };
                let (kind, values) = kinds.new_split_kind(kind, count).expect("a kind");
                let mut split = Split::new(kind, values, count, &mut new_id);
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
        NodeId::new(next)
    };
    let mut chain = Chain::serial([], &mut new_id);
    chain.root.branches[0] = Branch { nodes: top, ..chain.root.branches[0].clone() };
    (chain, devices)
}

pub(crate) fn chain() -> impl Strategy<Value = (Chain, Vec<DeviceId>)> {
    vec(shape(), 0..6).prop_map(|top| build(&top))
}

proptest! {
    #![proptest_config(config())]

    /// A chain written as its file has it and read again is the same chain.
    #[test]
    fn a_chain_written_and_read_again_is_the_same((chain, devices) in chain()) {
        prop_assert_eq!(chain.validate(&devices, &SplitKinds::builtin()), Ok(()));
        let text = serde_json::to_string(&chain).expect("a chain is written");
        let read: Chain = serde_json::from_str(&text).expect("a chain is read");
        prop_assert_eq!(read, chain);
    }

    /// After the devices of an owner change in any way (some go, new ones
    /// come, in any place of the list), the chain fits them: it names each
    /// device of the owner one time and passes its check, and the devices
    /// that stayed keep their order.
    #[test]
    fn a_chain_fits_any_change_of_its_devices(
        (mut chain, devices) in chain(),
        keep in vec(any::<bool>(), 32),
        added in vec(any::<Index>(), 0..4),
    ) {
        let kept: Vec<DeviceId> = devices.iter().zip(keep.iter().cycle()).filter(|(_, k)| **k).map(|(d, _)| *d).collect();
        let mut now = kept.clone();
        for (n, at) in added.iter().enumerate() {
            now.insert(at.index(now.len() + 1), DeviceId::new(500 + n as u64));
        }
        chain.fit(&now);
        prop_assert_eq!(chain.validate(&now, &SplitKinds::builtin()), Ok(()));
        let mut named = chain.devices();
        let stayed: Vec<DeviceId> = named.iter().copied().filter(|id| kept.contains(id)).collect();
        prop_assert_eq!(stayed, kept, "the devices that stayed keep their order");
        named.sort_unstable();
        let mut want = now.clone();
        want.sort_unstable();
        prop_assert_eq!(named, want, "each device one time");
    }
}
