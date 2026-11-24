//! A word of a script read as an enum that serde knows: the fields that
//! `paw.api` sets by name. The enum's serde names are the words, so the
//! words and the saved names stay the same.

use serde::de::{DeserializeOwned, IntoDeserializer, value};

/// The variant of `T` that `word` names, or `None` for a word that `T`
/// does not have.
pub(crate) fn from_word<T: DeserializeOwned>(word: &str) -> Option<T> {
    T::deserialize(IntoDeserializer::<value::Error>::into_deserializer(word)).ok()
}
