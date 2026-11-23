use serde_json::json;

use super::*;

/// A split of `kind` with the branches `branches` (each a list of nodes),
/// and the ids that `next` gives.
fn split(kind: &str, branches: Vec<Vec<Node>>, next: &mut Id) -> Split {
    let mut new_id = || {
        *next += 1;
        *next
    };
    let (word, values) = SplitKinds::default().new_split_kind(kind, branches.len()).expect("a kind");
    let mut s = Split::new(word, values, branches.len(), &mut new_id);
    for (branch, nodes) in s.branches.iter_mut().zip(branches) {
        branch.nodes = nodes;
    }
    s
}

fn device(id: Id) -> Node {
    Node::Device(id)
}

fn graph(nodes: Vec<Node>, next: &mut Id) -> Graph {
    Graph { root: split("chain", vec![nodes], next), taps: Vec::new() }
}

/// Check that the graph of the devices 1 to 5 gives `want`.
fn check(graph: &Graph, want: Result<(), &str>) {
    let got = graph.validate(&[1, 2, 3, 4, 5], &SplitKinds::default()).map_err(|e| e.to_string());
    assert_eq!(got.as_ref().map(|_| ()).map_err(String::as_str), want, "{graph:?}");
}

#[test]
fn a_good_graph_passes() {
    let mut next = 100;
    let layer = split("layer", vec![vec![device(2)], vec![device(3)]], &mut next);
    let g = graph(vec![device(1), Node::Split(Box::new(layer)), device(4), device(5)], &mut next);
    check(&g, Ok(()));
}

#[test]
fn validate_refuses_each_bad_graph_with_its_message() {
    let mut next = 100;
    let tap = |device, from| Tap { device, from: Some(from) };
    let cases: Vec<(&str, Graph, &str)> = vec![
        (
            "a tap to a later node",
            Graph { taps: vec![tap(1, 3)], ..graph(vec![device(1), device(2), device(3)], &mut next) },
            "device 1 takes its key from node 3, which comes later in the signal",
        ),
        (
            "a tap to itself",
            Graph { taps: vec![tap(2, 2)], ..graph(vec![device(2)], &mut next) },
            "device 2 takes its key from node 2, which holds it: that is a loop",
        ),
        (
            "a mid/side split with three branches",
            graph(vec![Node::Split(Box::new(split("ms", vec![vec![], vec![], vec![]], &mut next)))], &mut next),
            "a ms split takes 2 to 2 branches, not 3",
        ),
        (
            "a band split with one band",
            graph(vec![Node::Split(Box::new(split("band", vec![vec![]], &mut next)))], &mut next),
            "a band split takes 2 to 6 branches, not 1",
        ),
        {
            let mut band = split("band", vec![vec![], vec![], vec![]], &mut next);
            band.values.insert("xover".into(), json!([2000.0, 120.0]));
            (
                "crossovers out of order",
                graph(vec![Node::Split(Box::new(band))], &mut next),
                "the crossovers of a band split go from low to high: 120 Hz comes after 2000 Hz",
            )
        },
        {
            let mut band = split("band", vec![vec![], vec![]], &mut next);
            band.values.insert("xover".into(), json!([120.0, 2000.0]));
            (
                "too many crossovers",
                graph(vec![Node::Split(Box::new(band))], &mut next),
                "a band split with 2 bands takes 1 crossovers, not 2",
            )
        },
        (
            "a device of another track",
            graph(vec![device(9)], &mut next),
            "the graph names device 9, which is not on its track",
        ),
        ("a device twice", graph(vec![device(1), device(1)], &mut next), "the id 1 is in the graph twice"),
        (
            "a kind no one defined",
            {
                let mut s = split("layer", vec![vec![]], &mut next);
                s.kind = "transient".parse().unwrap();
                graph(vec![Node::Split(Box::new(s))], &mut next)
            },
            "no kind of split is called `transient`: say chain, layer, band, ms, lr, key, vel, select, outs or a kind of an extension",
        ),
    ];
    for (what, graph, message) in cases {
        let got = graph.validate(&[1, 2, 3, 4, 5], &SplitKinds::default()).map_err(|e| e.to_string());
        assert_eq!(got, Err(message.to_owned()), "{what}");
    }
}

#[test]
fn a_tap_to_the_split_around_the_listener_is_a_loop() {
    let mut next = 100;
    let rack = split("chain", vec![vec![device(2)]], &mut next);
    let id = rack.id;
    let g =
        Graph { taps: vec![Tap { device: 2, from: Some(id) }], ..graph(vec![Node::Split(Box::new(rack))], &mut next) };
    check(&g, Err(&format!("device 2 takes its key from node {id}, which holds it: that is a loop")));
}

#[test]
fn a_tap_to_a_node_that_ends_before_the_listener_passes() {
    let mut next = 100;
    let layer = split("layer", vec![vec![device(1)], vec![device(2)]], &mut next);
    let id = layer.id;
    let mut g = graph(vec![Node::Split(Box::new(layer)), device(3)], &mut next);
    // An earlier branch of the same split, the split before, the input.
    g.taps = vec![Tap { device: 2, from: Some(1) }, Tap { device: 3, from: Some(id) }, Tap { device: 1, from: None }];
    check(&g, Ok(()));
}

#[test]
fn an_extension_kind_takes_the_branches_it_defined() {
    let mut kinds = SplitKinds::default();
    kinds.define("transient".parse().unwrap(), KindSpec { min: 2, max: 2, first: 2 }).unwrap();
    let mut next = 100;
    let mut s = split("layer", vec![vec![device(1)], vec![]], &mut next);
    s.kind = "transient".parse().unwrap();
    let g = graph(vec![Node::Split(Box::new(s))], &mut next);
    assert_eq!(g.validate(&[1], &kinds), Ok(()));
    let refused = kinds.define("band".parse().unwrap(), KindSpec { min: 1, max: 2, first: 1 });
    assert_eq!(
        refused.map_err(|e| e.to_string()),
        Err("`band` is a kind of split of paw: an extension cannot define it again".to_owned())
    );
}

#[test]
fn fit_drops_devices_that_went_and_puts_new_ones_after_the_node_before_them() {
    let mut next = 100;
    let layer = split("layer", vec![vec![device(2)], vec![device(3)]], &mut next);
    let mut g = graph(vec![device(1), Node::Split(Box::new(layer.clone())), device(4)], &mut next);
    // 4 went; 6 comes after 3 (inside the layer), 7 at the start.
    assert!(g.fit(&[7, 1, 2, 3, 6]));
    assert_eq!(g.devices(), [7, 1, 2, 3, 6]);
    let top: Vec<Id> = g.root.branches[0].nodes.iter().map(Node::id).collect();
    assert_eq!(top, [7, 1, layer.id, 6], "a new device goes after the top node that holds the one before it");
    assert!(!g.fit(&[7, 1, 2, 3, 6]), "a graph that fits stays");
}
