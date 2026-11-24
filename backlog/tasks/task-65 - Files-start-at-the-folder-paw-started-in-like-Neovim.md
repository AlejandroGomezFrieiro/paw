---
id: TASK-65
title: 'Files: start at the folder paw started in, like Neovim'
status: Done
assignee: []
created_date: '2026-11-22T05:38:00Z'
updated_date: '2026-11-22T06:09:00Z'
labels:
  - files
  - ux
milestone: m-4
dependencies: []
priority: high
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: file loading and saving should start at the project folder or the folder paw started in, with relative names, `..` and `~` to go elsewhere, like Neovim. Today: relative names already go to paw.files.here() (the :cd folder, else beside the project, else where paw started; views/files.lua:71), and :cd/:pwd exist. But bare `:w` on a project with no file calls paw.frontend.save_as() (frontend.tl:1674), a directory picker (paw.pick.file) that seems to start in the home folder. Do: (1) every file picker and prompt (save_as, :e/:open/:import/:render pickers, the window's native dialog start folder) starts at paw.files.here(); (2) decide bare `:w` on a new project, Neovim-style: Neovim says E32 No file name; recommend: a prompt 'Save as: ' prefilled with here()/song name, completion of relative paths with .. and ~, or keep the picker but starting at here() — pick the most Neovim-like and say why; (3) path completion in the command line handles .., ~ and relative names from here(); (4) :pwd and the docs explain the rule in one place. Tests with real keys (start paw in a scratch folder, new project, :w song -> scratch/song; the picker starts in the scratch folder; :w ../other; :w ~/x with a scratch HOME).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a78c21b786a5eb798, commit 49d855c5. Pickers/dialogs/render default/save_as start at paw.files.here() (pick_dir removed); bare :w on a new project = prompt 'Save as (folder):' prefilled with project name, Tab completes, .. and ~ resolve; completion of '..' and '~' alone; docs cmdline.md + save-and-open how-to; test in guides_projects.lua.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged: pickers/dialogs start at paw.files.here(); new project :w prompts 'Save as (folder):' with relative names, .. and ~; pick_dir removed.
<!-- SECTION:FINAL_SUMMARY:END -->
