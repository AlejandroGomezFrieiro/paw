//! `paw.api.tempo_*`: the tempo map for Lua. The conversions are called for
//! every clip and line a view draws, so they read the project's map in
//! place: a binary search, no copying.

use std::rc::Rc;

use paw_engine::{SigPoint, TempoMap, TempoPoint};
use mlua::{Lua, Table, Value as LuaValue};
use serde::Deserialize;

use crate::api::{LuaResult, Shared, from_lua};

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
        |lua, m, (from, to, limit): (f64, f64, Option<usize>)| {
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
        },
    )?;
    // Every point: `{ tempos = { { beat, bpm, ramp } }, signatures = { { beat, num, den, bar } } }`.
    // @return types.TempoPoints
    reader(lua, api, shared, "tempo_points", |lua, m, ()| {
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
    })?;

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
