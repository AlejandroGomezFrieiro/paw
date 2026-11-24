//! Free names: a name that is not taken yet, made from a wanted name and a
//! number. The user sees these names (files on the disk, subprojects), so
//! each caller keeps the scheme that it had.

/// How the number goes into a name that is taken.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Scheme {
    /// `a.2.wav`: the files that go to the trash.
    Dot,
    /// `a-2.wav`: uploads, the files of a project folder, stems.
    Dash,
    /// `Verse 2`: subprojects.
    Space,
}

/// `stem` and `ext` as one name if that is free, else the first free name
/// with a number from 2. `ext` is empty or starts with its dot. `taken`
/// tells whether a name is taken.
pub(crate) fn free(taken: impl Fn(&str) -> bool, stem: &str, ext: &str, scheme: Scheme) -> String {
    let first = format!("{stem}{ext}");
    if !taken(&first) {
        return first;
    }
    let separator = match scheme {
        Scheme::Dot => '.',
        Scheme::Dash => '-',
        Scheme::Space => ' ',
    };
    // The numbers do not end, and each name can be taken only once.
    (2u64..)
        .map(|n| format!("{stem}{separator}{n}{ext}"))
        .find(|name| !taken(name))
        .unwrap_or(first)
}

/// A file name as its stem and its extension with the dot: `a.wav` gives
/// `a` and `.wav`. A name with no dot, or whose only dot is the first
/// character, has no extension.
pub(crate) fn split_ext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(at) if at > 0 => name.split_at(at),
        _ => (name, ""),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The names that are taken in the tests.
    const TAKEN: [&str; 5] = ["a.wav", "a.2.wav", "a-2.wav", "Verse", "Verse 2"];

    fn check(stem: &str, ext: &str, scheme: Scheme, want: &str) {
        let name = free(|name| TAKEN.contains(&name), stem, ext, scheme);
        assert_eq!(name, want, "{stem}{ext} in the scheme {scheme:?}");
    }

    #[test]
    fn a_free_name_is_kept() {
        check("b", ".wav", Scheme::Dash, "b.wav");
    }

    #[test]
    fn the_dot_scheme_puts_the_number_before_the_extension() {
        check("a", ".wav", Scheme::Dot, "a.3.wav");
    }

    #[test]
    fn the_dash_scheme_joins_the_number_with_a_dash() {
        check("a", ".wav", Scheme::Dash, "a-3.wav");
    }

    #[test]
    fn the_space_scheme_joins_the_number_with_a_space() {
        check("Verse", "", Scheme::Space, "Verse 3");
    }

    #[test]
    fn a_name_splits_at_its_last_dot_unless_that_is_the_first_character() {
        assert_eq!(split_ext("take.1.wav"), ("take.1", ".wav"));
        assert_eq!(split_ext(".hidden"), (".hidden", ""));
        assert_eq!(split_ext("readme"), ("readme", ""));
    }
}
