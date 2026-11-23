use serde_json::json;

use super::*;
use crate::model::Track;

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

fn device(id: Id) -> DeviceInst {
    serde_json::from_value(json!({ "id": id, "kind": "gain", "bypass": false, "params": { "gain": 0.0, "pan": 0.0 } }))
        .expect("a device")
}

fn devices(doc: &Document, track: Id) -> Vec<Id> {
    doc.project.track(track).unwrap().devices.iter().map(|d| d.id).collect()
}

fn graph(doc: &Document, track: Id) -> Graph {
    (**doc.project.track(track).unwrap().graph.as_ref().expect("a graph")).clone()
}

fn param(doc: &Document, device: Id, key: &str) -> f64 {
    doc.project.device(device).expect("the device").params[key]
}

#[test]
fn each_edit_of_the_graph_is_one_undo_step() {
    type Setup = fn(&mut Document) -> Id;
    type Edit = fn(&mut Document, Id) -> Result<()>;
    let none: Setup = |_| 0;
    let layer: Setup = |doc| doc.graph_wrap(&[12], "layer", WrapOpts::default()).unwrap();
    let cases: Vec<(&str, Setup, Edit)> = vec![
        ("wrap", none, |doc, _| doc.graph_wrap(&[12, 11], "layer", WrapOpts::default()).map(drop)),
        ("unwrap", layer, |doc, split| doc.graph_unwrap(split, None).map(drop)),
        ("add a branch", layer, |doc, split| doc.graph_branch_add(split, Some("Crush".into()), None).map(drop)),
        ("move a node", layer, |doc, _| doc.graph_move(13, &Place { before: Some(11), ..Place::default() })),
        ("set a value of a split", layer, |doc, split| doc.graph_set(split, "mix", json!(0.5))),
        ("set a value of a branch", layer, |doc, split| {
            let branch = graph(doc, 1).root.split(split).unwrap().branches[1].id;
            doc.graph_set(branch, "gain", json!(-6.0))
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
fn a_wrap_makes_the_graph_and_keeps_the_signal_order() {
    let mut doc = document();
    let split = doc.graph_wrap(&[12, 13], "band", WrapOpts::default()).unwrap();
    let g = graph(&doc, 1);
    let band = g.root.split(split).unwrap();
    assert_eq!(band.kind.as_str(), "band");
    assert_eq!(band.values["xover"], json!([120.0, 2000.0]), "three bands, with their crossovers");
    assert_eq!(band.branches[0].nodes, [Node::Device(12), Node::Device(13)]);
    assert_eq!(devices(&doc, 1), [11, 12, 13]);
    // A device added at the end of the list goes at the end of the root.
    doc.edit(|p| {
        p.track_mut(1).unwrap().devices.push(Arc::new(device(14)));
        Ok(())
    })
    .unwrap();
    let top: Vec<Id> = graph(&doc, 1).root.branches[0].nodes.iter().map(Node::id).collect();
    assert_eq!(top, [11, split, 14]);
}

#[test]
fn a_move_puts_the_devices_in_the_new_signal_order() {
    let mut doc = document();
    let split = doc.graph_wrap(&[12], "layer", WrapOpts::default()).unwrap();
    let second = graph(&doc, 1).root.split(split).unwrap().branches[1].id;
    doc.graph_move(11, &Place { branch: Some(second), ..Place::default() }).unwrap();
    assert_eq!(devices(&doc, 1), [12, 11, 13], "the engine plays them in this order");
}

#[test]
fn an_unwrap_that_keeps_one_branch_takes_the_others_devices_from_the_track() {
    let mut doc = document();
    let split = doc.graph_wrap(&[12], "layer", WrapOpts::default()).unwrap();
    let second = graph(&doc, 1).root.split(split).unwrap().branches[1].id;
    doc.graph_move(13, &Place { branch: Some(second), ..Place::default() }).unwrap();
    assert_eq!(doc.graph_unwrap(split, Some(second)).unwrap(), 1, "one device went");
    assert_eq!(devices(&doc, 1), [11, 13]);
}

#[test]
fn a_refused_edit_says_why_and_changes_nothing() {
    let mut doc = document();
    let split = doc.graph_wrap(&[12, 13], "band", WrapOpts::default()).unwrap();
    doc.checkpoint();
    let before = serde_json::to_string(&doc.project).unwrap();
    let cases = [
        (
            doc.graph_set(split, "values", json!({ "xover": [2000.0, 120.0] })),
            "the crossovers of a band split go from low to high: 120 Hz comes after 2000 Hz",
        ),
        (doc.graph_set(split, "kind", json!("ms")), "a ms split takes 2 to 2 branches, not 3"),
        (doc.graph_tap(11, Some(Some(13))), "device 11 takes its key from node 13, which comes later in the signal"),
        (doc.graph_wrap(&[11, 13], "layer", WrapOpts::default()).map(drop), "the nodes to wrap are not in one branch"),
        (
            doc.graph_wrap(&[11], "fuzz", WrapOpts::default()).map(drop),
            "no kind of split is called `fuzz`: say chain, layer, band, ms, lr, key, vel, select, outs or a kind of an extension",
        ),
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
    let first = doc.graph_wrap(&[11, 12], "chain", WrapOpts::default()).unwrap();
    let rack = doc.rack_define(first, "Glue").unwrap();
    let second = doc.rack_place(rack, &Place { before: Some(21), ..Place::default() }).unwrap();
    let copies: Vec<Id> = graph(&doc, 2).root.split(second).unwrap().devices();
    assert_eq!(copies.len(), 2, "the instance has its own devices");
    assert_eq!(devices(&doc, 2)[..2], copies[..], "before the devices of its track");
    let def = |doc: &Document| doc.project.rack(rack).unwrap().split.devices();

    // An override on the second instance: the pan of its first device.
    doc.edit(|p| {
        p.device_mut(copies[0]).unwrap().params.insert("pan".into(), 0.5);
        Ok(())
    })
    .unwrap();
    // The definition changes the gain and the pan of that device.
    let first_device = def(&doc)[0];
    let key = |field: &str| format!("{first_device}.params.{field}");
    doc.rack_set(rack, &key("gain"), json!(-3.0)).unwrap();
    doc.rack_set(rack, &key("pan"), json!(-0.5)).unwrap();
    assert_eq!(param(&doc, 11, "gain"), -3.0, "the first instance follows");
    assert_eq!(param(&doc, 11, "pan"), -0.5);
    assert_eq!(param(&doc, copies[0], "gain"), -3.0, "the second instance follows");
    assert_eq!(param(&doc, copies[0], "pan"), 0.5, "its override stays");
    assert_eq!(doc.project.rack_overrides(second).unwrap(), [key("pan")]);

    // A new part of one instance reaches the other: 13 moves into the first.
    let branch = graph(&doc, 1).root.split(first).unwrap().branches[0].id;
    doc.graph_move(13, &Place { branch: Some(branch), ..Place::default() }).unwrap();
    assert_eq!(def(&doc).len(), 3, "the definition has the new device");
    assert_eq!(graph(&doc, 2).root.split(second).unwrap().devices().len(), 3, "so has the other instance");
    assert_eq!(param(&doc, copies[0], "pan"), 0.5, "and its override stays");

    // A reset gives the definition's value back.
    assert_eq!(doc.rack_reset(second).unwrap(), 1);
    assert_eq!(param(&doc, copies[0], "pan"), -0.5);
    assert!(doc.project.rack_overrides(second).unwrap().is_empty());
}

#[test]
fn a_linked_rack_cannot_go_inside_another() {
    let mut doc = document();
    let first = doc.graph_wrap(&[11], "chain", WrapOpts::default()).unwrap();
    let rack = doc.rack_define(first, "Glue").unwrap();
    let branch = graph(&doc, 1).root.split(first).unwrap().branches[0].id;
    let refused = doc.rack_place(rack, &Place { branch: Some(branch), ..Place::default() });
    assert!(refused.unwrap_err().to_string().contains("is inside another linked rack"));
}
