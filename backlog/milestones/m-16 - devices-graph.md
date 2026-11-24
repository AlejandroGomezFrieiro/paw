---
id: m-16
title: "Devices graph"
---

## Description

The device panel becomes a graph of devices: serial chains, splits (layer, band, mid/side, left/right, key, velocity, select, outs), racks with macros, templates, modulation, and a text language for the chain. The design is backlog/docs/designs/devices-graph.md (the sketch page is in the design agent's scratchpad). It was tested on three metal chains of 12 to 36 devices (section 9), and the mixing reference for the chains is the skill mixing-mastering, references/metal.md.

The goals: a chain of 20 devices fits in a few rows (folds, wrap, racks); the grammar follows Vim and the key rule, with the five modes of paw (section 5.6); the chain is a text language (section 10) that a person and an agent can edit, with a parser, checks, lints, a formatter and render checks, so a chain is always testable.

Order: the owner answers the questions of section 12 first (the first ticket). Then the kernel model, then the engine, the view and the chain language in parallel, then the rest. Each ticket brings its docs; the last ticket is the final pass of the docs.
