---
id: TASK-278
title: 'Devices graph: the owner answers the design questions (G0)'
status: Done
assignee: []
created_date: '2026-11-23T11:57:00Z'
updated_date: '2026-11-23T13:37:00Z'
labels:
  - devices-graph
milestone: m-16
dependencies: []
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 340000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The design of the devices graph has 27 open questions with recommendations (section 12 of the design). The later tickets depend on the answers: the tree model, the file on disk, the modes, linked racks, the chain language. The design agent recommends an answer for each one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The owner has answered each question of section 12, or accepted the recommendation
- [ ] #2 The design doc records each answer and each change that it causes, and the tickets of this milestone agree with the answers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-23 15:40: 'Let's go with the agents recommendations right now'. All 27 questions take the recommendation in devices-graph.md section 12 (Q2 changed: the chain language is the file on disk; Q25 the language is 'chain', file devices.chain; Q26 checks run only on request; Q27 paw formats on save). Later owner decisions in force: the language and chain-lsp are generic and never depend on paw; paw plugs the server in through an opt-in extension like midilsp.
<!-- SECTION:NOTES:END -->
