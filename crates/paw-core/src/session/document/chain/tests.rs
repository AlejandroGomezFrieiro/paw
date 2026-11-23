use serde_json::json;

use super::*;
use crate::model::chain::Node;
use crate::model::ids::TrackId;
use crate::model::{Id, Track};

/// A document with one track (id 1) of the devices 11, 12 and 13, a
/// second track (id 2) of the devices 21 and 22, and ids from 100 on.
fn document() -> Document {
    let mut doc = Document::default();
    doc.edit(|p| {
        for (track, devices) in [(1, [11, 12, 13].as_slice()), (2, &[21, 22])] {
            let mut t = Track::new(track);
            t.devices = devices.iter().map(|id| Arc::new(device(*id))).collect();
            p.tracks.push(Arc::new(t));
        }
        Ok(())
    })
    .unwrap();
    doc.next_id = 100;
    doc.checkpoint();
    doc
}

/// The owner track `n`.
fn track(n: u64) -> OwnerRef {
    OwnerRef::Track(TrackId::new(n))
}

fn n(id: u64) -> NodeId {
    NodeId::new(id)
}

fn device(id: Id) -> DeviceInst {
    serde_json::from_value(json!({ "id": id, "kind": "gain", "bypass": false, "params": { "gain": 0.0, "pan": 0.0 } }))
        .expect("a device")
}

fn devices(doc: &Document, owner: u64) -> Vec<Id> {
    doc.project.track(owner).unwrap().devices.iter().map(|d| d.id).collect()
}

fn chain(doc: &Document, owner: u64) -> Chain {
    (**doc.project.chain_of(track(owner)).expect("a chain")).clone()
}

fn param(doc: &Document, device: Id, key: &str) -> f64 {
    doc.project.device(device).expect("the device").params[key]
}

fn wrap(doc: &mut Document, owner: u64, nodes: &[u64], kind: &str) -> Result<NodeId> {
    let nodes: Vec<NodeId> = nodes.iter().copied().map(n).collect();
    doc.chain_wrap(track(owner), &nodes, kind, WrapOpts::default())
}

#[test]
fn each_edit_of_the_chain_is_one_undo_step() {
    type Setup = fn(&mut Document) -> NodeId;
    type Edit = fn(&mut Document, NodeId) -> Result<()>;
    let none: Setup = |_| n(0);
    let layer: Setup = |doc| wrap(doc, 1, &[12], "layer").unwrap();
    let cases: Vec<(&str, Setup, Edit)> = vec![
        ("wrap", none, |doc, _| wrap(doc, 1, &[12, 11], "layer").map(drop)),
        ("unwrap", layer, |doc, split| doc.chain_unwrap(track(1), split, None).map(drop)),
        ("add a branch", layer, |doc, split| doc.chain_branch_add(track(1), split, Some("Crush".into()), None).map(drop)),
        ("move a node", layer, |doc, _| doc.chain_move(track(1), n(13), &Place { before: Some(n(11)), ..Place::default() })),
        ("set a value of a split", layer, |doc, split| doc.chain_set(track(1), split, "mix", json!(0.5))),
        ("set a value of a branch", layer, |doc, split| {
            let branch = chain(doc, 1).root.split(split).unwrap().branches[1].id;
            doc.chain_set(track(1), branch, "gain", json!(-6.0))
        }),
    ];
    for (what, setup, edit) in cases {
        let mut doc = document();
        let id = setup(&mut doc);
        doc.checkpoint();
        let before = serde_json::to_string(&doc.project).unwrap();
        edit(&mut doc, id).unwrap_or_else(|e| panic!("{what}: {e}"));
        let after = serde_json::to_string(&doc.project).unwrap();
        assert_ne!(before, after, "{what} changes the project");
        assert!(doc.checkpoint(), "{what} makes an undo step");
        assert!(doc.undo(), "{what} is undone");
        assert_eq!(
            serde_json::to_string(&doc.project).unwrap(),
            before,
            "{what}: one undo gives the project before it"
        );
        assert!(doc.redo(), "{what} is redone");
        assert_eq!(serde_json::to_string(&doc.project).unwrap(), after, "{what}: the redo gives it again");
    }
}

#[test]
fn a_wrap_makes_the_chain_and_keeps_the_signal_order() {
    let mut doc = document();
    let split = wrap(&mut doc, 1, &[12, 13], "band").unwrap();
    let c = chain(&doc, 1);
    let band = c.root.split(split).unwrap();
    assert_eq!(band.kind.as_str(), "band");
    assert_eq!(band.values["xover"], json!([120.0, 2000.0]), "three bands, with their crossovers");
    assert_eq!(band.branches[0].nodes, [Node::Device(DeviceId::new(12)), Node::Device(DeviceId::new(13))]);
    assert_eq!(devices(&doc, 1), [11, 12, 13]);
    // A device added at the end of the list goes at the end of the root.
    doc.edit(|p| {
        p.track_mut(1).unwrap().devices.push(Arc::new(device(14)));
        Ok(())
    })
    .unwrap();
    let top: Vec<NodeId> = chain(&doc, 1).root.branches[0].nodes.iter().map(Node::id).collect();
    assert_eq!(top, [n(11), split, n(14)]);
}

#[test]
fn a_move_puts_the_devices_in_the_new_signal_order() {
    let mut doc = document();
    let split = wrap(&mut doc, 1, &[12], "layer").unwrap();
    let second = chain(&doc, 1).root.split(split).unwrap().branches[1].id;
    doc.chain_move(track(1), n(11), &Place { branch: Some(second), ..Place::default() }).unwrap();
    assert_eq!(devices(&doc, 1), [12, 11, 13], "the engine plays them in this order");
}

#[test]
fn an_unwrap_that_keeps_one_branch_takes_the_others_devices_from_the_owner() {
    let mut doc = document();
    let split = wrap(&mut doc, 1, &[12], "layer").unwrap();
    let second = chain(&doc, 1).root.split(split).unwrap().branches[1].id;
    doc.chain_move(track(1), n(13), &Place { branch: Some(second), ..Place::default() }).unwrap();
    assert_eq!(doc.chain_unwrap(track(1), split, Some(second)).unwrap(), 1, "one device went");
    assert_eq!(devices(&doc, 1), [11, 13]);
}

#[test]
fn a_refused_edit_says_why_and_changes_nothing() {
    let mut doc = document();
    let split = wrap(&mut doc, 1, &[12, 13], "band").unwrap();
    doc.checkpoint();
    let before = serde_json::to_string(&doc.project).unwrap();
    let cases = [
        (
            doc.chain_set(track(1), split, "values", json!({ "xover": [2000.0, 120.0] })),
            "the crossovers of a band split go from low to high: 120 Hz comes after 2000 Hz",
        ),
        (doc.chain_set(track(1), split, "kind", json!("ms")), "a ms split takes 2 to 2 branches, not 3"),
        (doc.chain_set(track(1), split, "meta", json!({})), "a split has no value `meta`: say name, mix, gain, kind or values"),
        (
            doc.chain_tap(track(1), DeviceId::new(11), Some(KeyFrom::Node(n(13)))),
            "device 11 takes its key from node 13, which comes later in the signal",
        ),
        (wrap(&mut doc, 1, &[11, 13], "layer").map(drop), "the nodes to wrap are not in one branch"),
        (
            wrap(&mut doc, 1, &[11], "fuzz").map(drop),
            "no kind of split is called `fuzz`: say chain, layer, band, ms, lr, key, vel, select, outs or a kind of an extension",
        ),
        (wrap(&mut doc, 2, &[11], "layer").map(drop), "no node 11 in the chain"),
        (wrap(&mut doc, 9, &[11], "layer").map(drop), "no track 9"),
    ];
    for (result, message) in cases {
        assert_eq!(result.map_err(|e| e.to_string()), Err(message.to_owned()));
    }
    assert_eq!(serde_json::to_string(&doc.project).unwrap(), before, "the project is as it was");
    assert!(!doc.checkpoint(), "no undo step");
}

#[test]
fn a_change_of_a_linked_rack_reaches_each_instance_and_an_override_stays() {
    let mut doc = document();
    let first = wrap(&mut doc, 1, &[11, 12], "chain").unwrap();
    let rack = doc.rack_define(track(1), first, "Glue").unwrap();
    let second = doc.rack_place(track(2), rack, &Place { before: Some(n(21)), ..Place::default() }).unwrap();
    let copies: Vec<Id> = chain(&doc, 2).root.split(second).unwrap().devices().into_iter().map(DeviceId::get).collect();
    assert_eq!(copies.len(), 2, "the instance has its own devices");
    assert_eq!(devices(&doc, 2)[..2], copies[..], "before the devices of its owner");
    let def = |doc: &Document| doc.project.rack(rack).unwrap().split.devices();

    // An override on the second instance: the pan of its first device.
    doc.edit(|p| {
        p.device_mut(copies[0]).unwrap().params.insert("pan".into(), 0.5);
        Ok(())
    })
    .unwrap();
    // The definition changes the gain and the pan of that device.
    let first_device = def(&doc)[0];
    let key = |param: &str| format!("#{first_device}.{param}");
    doc.rack_set(rack, &key("gain"), json!(-3.0)).unwrap();
    doc.rack_set(rack, &format!("{first_device}.params.pan"), json!(-0.5)).unwrap();
    assert_eq!(param(&doc, 11, "gain"), -3.0, "the first instance follows");
    assert_eq!(param(&doc, 11, "pan"), -0.5);
    assert_eq!(param(&doc, copies[0], "gain"), -3.0, "the second instance follows");
    assert_eq!(param(&doc, copies[0], "pan"), 0.5, "its override stays");
    let overrides: Vec<String> = doc.project.rack_overrides(track(2), second).unwrap().iter().map(ToString::to_string).collect();
    assert_eq!(overrides, [key("pan")]);

    // A new part of one instance reaches the other: 13 moves into the first.
    let branch = chain(&doc, 1).root.split(first).unwrap().branches[0].id;
    doc.chain_move(track(1), n(13), &Place { branch: Some(branch), ..Place::default() }).unwrap();
    assert_eq!(def(&doc).len(), 3, "the definition has the new device");
    assert_eq!(chain(&doc, 2).root.split(second).unwrap().devices().len(), 3, "so has the other instance");
    assert_eq!(param(&doc, copies[0], "pan"), 0.5, "and its override stays");

    // A reset gives the definition's value back.
    assert_eq!(doc.rack_reset(track(2), second).unwrap(), 1);
    assert_eq!(param(&doc, copies[0], "pan"), -0.5);
    assert!(doc.project.rack_overrides(track(2), second).unwrap().is_empty());
}

#[test]
fn a_linked_rack_cannot_go_inside_another() {
    let mut doc = document();
    let first = wrap(&mut doc, 1, &[11], "chain").unwrap();
    let rack = doc.rack_define(track(1), first, "Glue").unwrap();
    let branch = chain(&doc, 1).root.split(first).unwrap().branches[0].id;
    let refused = doc.rack_place(track(1), rack, &Place { branch: Some(branch), ..Place::default() });
    assert!(refused.unwrap_err().to_string().contains("is inside another linked rack"));
}
