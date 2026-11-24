---
id: TASK-7
title: 'Subprojects (nests with their own tracks): S0-S12'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T11:09:00Z'
labels:
  - nest
  - subprojects
  - epic
milestone: m-2
dependencies: []
priority: medium
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic. Do not build this ticket: build its children.

Proper subprojects with their own tracks, devices, mix, meter and tempo (a slow piano section in a metal song), on their own return row; `<Space>za` new, `<Space>zw`/`<Space>zW` save a view as one, `<Space>zp` promote back to a view, stems, links, own tempo, freeze, export and import, nest kinds. Design: backlog/docs/designs/nest.md sections 3.7, 3.9, 4, 5.2, 8.

S0 (the N0 spike) is done: section 8 of nest.md. Its finding is part S2a.

Children, in the order of nest.md 5.2. The owner combined chained children on 2026-11-22; the archived tickets say "Combined into TASK-N".
- TASK-7.2: S2a, copies share compiled events. Done.
- TASK-7.1: S1a, nest data and files. Done.
- TASK-7.3: S1b, S2b, S2c: a subproject is a scope, plays into its return row, with its own transport. Done. It absorbed TASK-7.4 and TASK-7.5.
- TASK-7.6: S3 to S6: <Space>za and :nest.new, the return row and blocks, K, :nest.list, stems, <Space>zp promotes. It absorbed TASK-7.7 and TASK-7.8.
- TASK-7.9: S7 and S8: <Space>zw and <Space>zW. It absorbed TASK-7.10.
- TASK-7.11: S9 and S10: own tempo and meter, two blocks of one subproject, :nest.unique. It absorbed TASK-7.12.
- TASK-7.13: S11, freeze a block (M).
- TASK-7.14: S12a, :nest.export and :scope.write <folder> (M).
- TASK-7.16: S12a part 2, :import of a project folder, :nest.own, :e of a path inside a song.
- TASK-7.15: S12b, projdiff sees changes inside subprojects (S). Follow-ups: TASK-210, TASK-211, TASK-212.
- TASK-7.17: S12c, nest kinds from extensions and nest events.
- TASK-213: freeze a block inside a subproject and a stem block (follow-up of TASK-7.13).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Split on 2026-11-22 into TASK-7.2 TASK-7.1 TASK-7.3 TASK-7.4 TASK-7.5 TASK-7.6 TASK-7.7 TASK-7.8 TASK-7.9 TASK-7.10 TASK-7.11 TASK-7.12 TASK-7.13 TASK-7.14 TASK-7.15. S0 was the N0 spike (done; nest.md section 8). Kept as an epic note: set it to Done when all children are merged.

Board review 2026-11-23: children left: TASK-7.13 (S11 freeze a block, in work), TASK-7.14 (S12a export and :scope.write <folder>), TASK-7.16 (S12a part 2: :import, :nest.own, :e song/nests/<name>), TASK-7.15 (S12b projdiff), TASK-7.17 (S12c nest kinds and events). TASK-7.14 and TASK-7.15 were split on this day. All other children are Done and on main.

PO 2026-11-23 (after 8e91e5b0): TASK-7.13 (S11) and TASK-7.15 (S12b) are Done and on main. Children left: TASK-7.14 (S12a, in the check of batch 14), TASK-7.16 (S12a part 2, in work), TASK-7.17 (S12c, in work), TASK-213 (freeze inside a subproject and a stem block, ready). Follow-ups outside the epic: TASK-210, TASK-211, TASK-212, TASK-214. The export design (TASK-222.7) later replaces :nest.export and :scope.write <folder> with :export project.

PO 2026-11-23 (owner: fewer, larger tickets): follow-ups now in bundles: TASK-211 (took TASK-212), TASK-257 (took TASK-265, TASK-258, TASK-259). TASK-224 and TASK-225 went into TASK-266 (m-15).

PO 2026-11-23 (after batch 16, cd367da1): all eleven children (TASK-7.1 to TASK-7.17) and TASK-213 are Done and on main. Epic set Done. Open follow-ups outside the epic: TASK-214, the UX tickets of m-15 (TASK-261, 264, 266), and the export tickets (TASK-222.x).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Subprojects S0-S12 are on main: data and files, scope and return row, transport, <Space>za/zw/zW/zp, own tempo and meter, freeze, export and import, projdiff, nest kinds and events.
<!-- SECTION:FINAL_SUMMARY:END -->
