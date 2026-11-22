//! `paw.api.tempo_*`: the tempo map for Lua. The conversions are called for
//! every clip and line a view draws, so they read the project's map in
//! place: a binary search, no copying.

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

use paw_engine::{SigPoint, TempoMap, TempoPoint};
use mlua::{AnyUserData, Lua, Table, UserData, UserDataFields, UserDataMethods, Value as LuaValue};
use serde::Deserialize;

use crate::api::{LuaResult, Shared, from_lua};
use crate::model::ClipContent;
use crate::model::nest::Timing;

#[derive(Deserialize)]
struct TempoIn {
    beat: f64,
    bpm: f64,
    #[serde(default)]
    ramp: bool,
}

#[derive(Deserialize)]
struct SigIn {
    beat: f64,
    num: u32,
    den: u32,
}

/// Register a function of the project's map.
fn reader<A, R>(
    lua: &Lua,
    api: &Table,
    shared: &Rc<Shared>,
    name: &str,
    f: impl Fn(&Lua, &TempoMap, A) -> mlua::Result<R> + 'static,
) -> mlua::Result<()>
where
    A: mlua::FromLuaMulti,
    R: mlua::IntoLuaMulti,
{
    let sh = shared.clone();
    api.set(
        name,
        lua.create_function(move |lua, args: A| {
            let session = sh.session.borrow();
            f(lua, session.project.tempo_map(), args)
        })?,
    )
}

pub fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    // @return number
    reader(lua, api, shared, "tempo_seconds", |_, m, beat: f64| {
        Ok(m.seconds(beat))
    })?;
    // @return number
    reader(lua, api, shared, "tempo_beat", |_, m, seconds: f64| {
        Ok(m.beat(seconds))
    })?;
    // @return number
    reader(lua, api, shared, "tempo_at", |_, m, beat: f64| {
        Ok(m.tempo(beat))
    })?;
    // @return integer, integer
    reader(lua, api, shared, "tempo_signature", |_, m, beat: f64| {
        Ok(m.signature(beat))
    })?;
    // Bars count from 0 here; `paw.tempo` and `paw.time` count from 1.
    // @return integer
    reader(lua, api, shared, "tempo_bar_of", |_, m, beat: f64| {
        Ok(m.bar_of(beat))
    })?;
    // @return number
    reader(lua, api, shared, "tempo_bar_start", |_, m, bar: i64| {
        Ok(m.bar_start(bar))
    })?;
    // @return number
    reader(lua, api, shared, "tempo_bar_length", |_, m, beat: f64| {
        Ok(m.bar_length(beat))
    })?;
    // @return integer, integer
    reader(lua, api, shared, "tempo_bar_signature", |_, m, bar: i64| {
        Ok(m.bar_signature(bar))
    })?;
    // @return boolean
    reader(lua, api, shared, "tempo_is_bar_line", |_, m, beat: f64| {
        Ok(m.is_bar_line(beat))
    })?;
    // @return integer, integer, number
    reader(lua, api, shared, "tempo_bbt", |_, m, beat: f64| {
        Ok(m.bbt(beat))
    })?;
    // @return number
    reader(
        lua,
        api,
        shared,
        "tempo_from_bbt",
        |_, m, (bar, beat, fraction): (i64, u32, Option<f64>)| {
            Ok(m.from_bbt(bar, beat, fraction.unwrap_or(0.0)))
        },
    )?;
    // The bar and beat lines from one beat to another: { beat, bar, index }
    // each, `index` 0 on a bar line. At most `limit` of them (default 10000).
    // @return {types.TempoLine}
    reader(
        lua,
        api,
        shared,
        "tempo_lines",
        |lua, m, (from, to, limit): (f64, f64, Option<usize>)| lines(lua, m, from, to, limit),
    )?;
    // Every point: `{ tempos = { { beat, bpm, ramp } }, signatures = { { beat, num, den, bar } } }`.
    // @return types.TempoPoints
    reader(lua, api, shared, "tempo_points", |lua, m, ()| points(lua, m))?;

    // The time of the subproject that block `clip` places, as the window
    // inside it counts it: its own tempo, its own meter, or both. Nil when
    // the subproject follows the song's tempo and meter: the song's map,
    // from the block's start, is its time then. The same conversions as
    // the `tempo_*` functions, as methods, in the subproject's beats, and
    // `song_beat(beat)` and `nest_beat(song_beat)` between its beats and
    // the song's.
    // @return types.NestTime
    let sh = shared.clone();
    let made: RefCell<Option<(NestTimeKey, AnyUserData)>> = RefCell::new(None);
    api.set(
        "nest_time",
        lua.create_function(move |lua, clip: crate::model::Id| {
            let session = sh.session.borrow();
            let p = &session.project;
            let Some(c) = p.clip(clip) else {
                return Ok(None);
            };
            let ClipContent::Nest { nest, offset, .. } = &c.content else {
                return Ok(None);
            };
            let Some(held) = p.nest(*nest) else {
                return Ok(None);
            };
            // The same block, subproject and song's map as last time: the
            // same table. The window asks for it at every line it draws.
            let key = NestTimeKey { clip: c.clone(), nest: held.clone(), song: p.tempo_map().clone() };
            if let Some((was, data)) = made.borrow().as_ref()
                && was.same(&key)
            {
                return Ok(Some(data.clone()));
            }
            let timing = held.timing(p.tempo_map(), None, c.start, *offset);
            let Some(map) = held.own_map(p.tempo_map(), timing.zero()) else {
                return Ok(None);
            };
            let data = lua.create_userdata(NestTime { map, timing, own_tempo: held.has_own_tempo() })?;
            *made.borrow_mut() = Some((key, data.clone()));
            Ok(Some(data))
        })?,
    )?;

    let sh = shared.clone();
    // @return nil
    api.set(
        "tempo_set",
        lua.create_function(move |_, (beat, bpm, ramp): (f64, f64, Option<bool>)| {
            sh.session.borrow_mut().tempo_set(beat, bpm, ramp).lua()
        })?,
    )?;
    let sh = shared.clone();
    // @return nil
    api.set(
        "tempo_remove",
        lua.create_function(move |_, beat: f64| sh.session.borrow_mut().tempo_remove(beat).lua())?,
    )?;
    let sh = shared.clone();
    // @return nil
    api.set(
        "signature_set",
        lua.create_function(move |_, (beat, num, den): (f64, u32, u32)| {
            sh.session.borrow_mut().signature_set(beat, num, den).lua()
        })?,
    )?;
    let sh = shared.clone();
    // @return nil
    api.set(
        "signature_remove",
        lua.create_function(move |_, beat: f64| {
            sh.session.borrow_mut().signature_remove(beat).lua()
        })?,
    )?;
    // Replace the whole map: `tempo_set_points({ { beat, bpm, ramp } }, { { beat, num, den } })`.
    // @param tempos {types.TempoPoint}
    // @param sigs {types.SigPoint}
    // @return nil
    let sh = shared.clone();
    api.set(
        "tempo_set_points",
        lua.create_function(move |lua, (tempos, sigs): (LuaValue, LuaValue)| {
            let tempos: Vec<TempoIn> = from_lua(lua, tempos)?;
            let sigs: Vec<SigIn> = from_lua(lua, sigs)?;
            let tempos = tempos
                .into_iter()
                .map(|p| TempoPoint {
                    beat: p.beat,
                    bpm: p.bpm,
                    ramp: p.ramp,
                })
                .collect();
            let sigs = sigs
                .into_iter()
                .map(|p| SigPoint {
                    beat: p.beat,
                    num: p.num,
                    den: p.den,
                })
                .collect();
            sh.session.borrow_mut().tempo_set_points(tempos, sigs).lua()
        })?,
    )?;
    Ok(())
}

/// `tempo_lines` of a map: at most `limit` lines (default 10000).
fn lines(lua: &Lua, m: &TempoMap, from: f64, to: f64, limit: Option<usize>) -> mlua::Result<Table> {
    let list = lua.create_table()?;
    let limit = limit.unwrap_or(10_000);
    if limit == 0 {
        return Ok(list);
    }
    let mut n = 0;
    let mut result = Ok(());
    m.lines(from, to, |line| {
        n += 1;
        result = (|| {
            let t = lua.create_table_with_capacity(0, 3)?;
            t.raw_set("beat", line.beat)?;
            t.raw_set("bar", line.bar + 1)?;
            t.raw_set("index", line.index)?;
            list.raw_set(n, t)
        })();
        n < limit && result.is_ok()
    });
    result.map(|_| list)
}

/// `tempo_points` of a map.
fn points(lua: &Lua, m: &TempoMap) -> mlua::Result<Table> {
    let out = lua.create_table()?;
    let tempos = lua.create_table()?;
    for (i, p) in m.tempos().enumerate() {
        let t = lua.create_table()?;
        t.raw_set("beat", p.beat)?;
        t.raw_set("bpm", p.bpm)?;
        t.raw_set("ramp", p.ramp)?;
        tempos.raw_set(i + 1, t)?;
    }
    let sigs = lua.create_table()?;
    for (i, p) in m.signatures().enumerate() {
        let t = lua.create_table()?;
        t.raw_set("beat", p.beat)?;
        t.raw_set("num", p.num)?;
        t.raw_set("den", p.den)?;
        t.raw_set("bar", m.bar_of(p.beat) + 1)?;
        sigs.raw_set(i + 1, t)?;
    }
    out.raw_set("tempos", tempos)?;
    out.raw_set("signatures", sigs)?;
    Ok(out)
}

/// What a `nest_time` table was made from: the block, its subproject and
/// the song's map. A change of one makes a new value of it.
struct NestTimeKey {
    clip: Arc<crate::model::Clip>,
    nest: Arc<crate::model::Nest>,
    song: Arc<TempoMap>,
}

impl NestTimeKey {
    fn same(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.clip, &other.clip) && Arc::ptr_eq(&self.nest, &other.nest) && Arc::ptr_eq(&self.song, &other.song)
    }
}

/// `paw.api.nest_time`: a subproject's own map, and where its beats are in
/// the song for one block.
struct NestTime {
    map: TempoMap,
    timing: Timing,
    own_tempo: bool,
}

impl UserData for NestTime {
    fn add_fields<F: UserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("own_tempo", |_, t| Ok(t.own_tempo));
    }

    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("song_beat", |_, t, beat: f64| Ok(t.timing.song_beat(beat)));
        methods.add_method("nest_beat", |_, t, beat: f64| Ok(t.timing.nest_beat(beat)));
        methods.add_method("seconds", |_, t, beat: f64| Ok(t.map.seconds(beat)));
        methods.add_method("beat", |_, t, seconds: f64| Ok(t.map.beat(seconds)));
        methods.add_method("tempo", |_, t, beat: f64| Ok(t.map.tempo(beat)));
        methods.add_method("signature", |_, t, beat: f64| Ok(t.map.signature(beat)));
        methods.add_method("bar_of", |_, t, beat: f64| Ok(t.map.bar_of(beat)));
        methods.add_method("bar_start", |_, t, bar: i64| Ok(t.map.bar_start(bar)));
        methods.add_method("bar_length", |_, t, beat: f64| Ok(t.map.bar_length(beat)));
        methods.add_method("bar_signature", |_, t, bar: i64| Ok(t.map.bar_signature(bar)));
        methods.add_method("is_bar_line", |_, t, beat: f64| Ok(t.map.is_bar_line(beat)));
        methods.add_method("bbt", |_, t, beat: f64| Ok(t.map.bbt(beat)));
        methods.add_method("from_bbt", |_, t, (bar, beat, fraction): (i64, u32, Option<f64>)| {
            Ok(t.map.from_bbt(bar, beat, fraction.unwrap_or(0.0)))
        });
        methods.add_method("lines", |lua, t, (from, to, limit): (f64, f64, Option<usize>)| {
            lines(lua, &t.map, from, to, limit)
        });
        methods.add_method("points", |lua, t, ()| points(lua, &t.map));
    }
}

/// `paw.api.tempo_from_seconds`.
pub fn from_seconds(lua: &Lua, tempos: &Table, sigs: Option<&Table>) -> mlua::Result<Table> {
    let mut points = Vec::new();
    for p in tempos.sequence_values::<Table>() {
        let p = p?;
        points.push((p.get::<Option<f64>>("seconds")?.unwrap_or(0.0), p.get::<f64>("bpm")?, p.get::<Option<bool>>("ramp")?.unwrap_or(false)));
    }
    let mut signatures = Vec::new();
    if let Some(sigs) = sigs {
        for p in sigs.sequence_values::<Table>() {
            let p = p?;
            signatures.push((p.get::<Option<f64>>("seconds")?.unwrap_or(0.0), p.get::<u32>("num")?, p.get::<u32>("den")?));
        }
    }
    let map = std::rc::Rc::new(TempoMap::from_seconds(&points, &signatures));
    let out = lua.create_table()?;
    let list = lua.create_table()?;
    for p in map.tempos() {
        let t = lua.create_table()?;
        t.set("beat", p.beat)?;
        t.set("bpm", p.bpm)?;
        t.set("ramp", p.ramp)?;
        list.push(t)?;
    }
    out.set("tempos", list)?;
    let list = lua.create_table()?;
    for p in map.signatures() {
        let t = lua.create_table()?;
        t.set("beat", p.beat)?;
        t.set("num", p.num)?;
        t.set("den", p.den)?;
        list.push(t)?;
    }
    out.set("signatures", list)?;
    let m = map.clone();
    out.set("beat", lua.create_function(move |_, seconds: f64| Ok(m.beat(seconds)))?)?;
    out.set("seconds", lua.create_function(move |_, beat: f64| Ok(map.seconds(beat)))?)?;
    Ok(out)
}
