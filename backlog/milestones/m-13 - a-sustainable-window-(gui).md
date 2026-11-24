---
id: m-13
title: "A sustainable window (GUI)"
---

## Description

Low priority. Do not start until every other milestone is finished and the owner says to start. Goal: a graphical window that stays in step with the terminal at low cost: it draws the same scenes as the terminal (one view, two frontends), it has tests that do not need an X server (kittest), it is in the default build again, and a change of a view cannot break it without a failed check. First step: a design that says why the window fell behind (the window paused 2026-11-22, the arrange modules moved to Teal, the old .lua paths) and how to keep it in step. Tickets of the window that wait here: TASK-160, TASK-193, TASK-77.4.
