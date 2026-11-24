//! Property tests of the undo file: a tree of states written and read again.
#![cfg_attr(test, expect(clippy::cast_possible_truncation, reason = "debt: pay down"))]

use std::collections::BTreeMap;
use std::path::PathBuf;

use proptest::collection::{btree_map, vec};
use proptest::prelude::*;
use proptest::sample::Index;

use super::{StateEntry, Store, TreeFile, read_tree};
use crate::props::config;

/// The files of one state: paths of one to three parts, so that folders
/// hold files and folders, and a name can be both a file and a folder.
fn files() -> impl Strategy<Value = BTreeMap<PathBuf, Vec<u8>>> {
    let path = vec("[a-z0-9_]{1,4}", 1..4).prop_map(|parts| parts.iter().collect::<PathBuf>());
    btree_map(path, vec(any::<u8>(), 0..48), 0..6)
}

/// What a state is made of, but its links and its files' blob.
#[derive(Clone, Debug)]
struct Made {
    /// The state it hangs from: one made before it.
    parent: Index,
    files: BTreeMap<PathBuf, Vec<u8>>,
    time: f64,
    label: Option<String>,
    keys: Option<String>,
    name: Option<String>,
    keep: bool,
}

fn made() -> impl Strategy<Value = Made> {
    let text = || prop::option::of("\\PC{0,8}");
    (any::<Index>(), files(), 0.0..2e9f64, text(), text(), text(), any::<bool>()).prop_map(
        |(parent, files, time, label, keys, name, keep)| Made { parent, files, time, label, keys, name, keep },
    )
}

proptest! {
    #![proptest_config(config())]

    /// An undo file written and read again gives each state with its links,
    /// its words and its files.
    #[test]
    fn an_undo_file_comes_back_with_the_files_of_each_state(
        made in vec(made(), 1..5),
        saved in any::<Index>(),
    ) {
        let dir = tempfile::tempdir().expect("a scratch folder");
        let mut store = Store::new(dir.path());
        let mut states: Vec<StateEntry> = Vec::new();
        for (id, m) in made.iter().enumerate() {
            let parent = (id > 0).then(|| m.parent.index(id) as u64);
            if let Some(parent) = parent {
                let p = &mut states[parent as usize];
                p.children.push(id as u64);
                p.redo = Some(id as u64);
            }
            states.push(StateEntry {
                id: id as u64,
                parent,
                children: Vec::new(),
                redo: None,
                time: m.time,
                label: m.label.clone(),
                keys: m.keys.clone(),
                name: m.name.clone(),
                keep: m.keep,
                files: store.put_files(&m.files).expect("the blobs are written"),
            });
        }
        let saved = saved.index(states.len()) as u64;
        let mut tree = TreeFile::new(0, saved, states).expect("every link names a state");

        let dropped = store.commit(&mut tree, u64::MAX).expect("the undo file is written");
        let read = read_tree(dir.path()).expect("the undo file is read");

        prop_assert!(dropped.is_empty(), "no state is dropped with no limit: {:?}", dropped);
        prop_assert_eq!(read.as_ref(), Some(&tree));
        // A new store reads the blobs from the folder alone.
        let mut store = Store::new(dir.path());
        for (state, m) in tree.states.iter().zip(&made) {
            let read: BTreeMap<PathBuf, Vec<u8>> = store
                .read_files(state.files)
                .expect("the files of a state are read")
                .into_iter()
                .map(|(path, bytes)| (path, bytes.to_vec()))
                .collect();
            prop_assert_eq!(&read, &m.files, "the files of state {}", state.id);
        }
    }
}
