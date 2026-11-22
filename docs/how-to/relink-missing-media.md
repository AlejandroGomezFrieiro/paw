# How to relink lost media

<!-- tags: relink-missing-media -->

You can find the sound files of a project again after you move them. Each
command is in [Media files and audio clips](../reference/media.md).

1. Open the project. A message lists the files that paw cannot find, and
   their clips show "offline".
2. Type `:media.relink`, and paw lists the lost files.
3. Select a file, and then select the file that it is now. paw looks for
   the other lost files next to it. If paw still cannot find some files,
   type `:media.relink` again, select "Search a directory", and select the
   directory.
4. Save the project, and the new paths go into the project file.

In the graphical window, select File → Sound files, and then the entry
that finds the lost files.

To give a directory on the command line, type `:media.relink ~/samples`.

If you want to keep a project complete for a move to another computer,
type `:media.collect`. paw copies each file from outside the project
folder into `media`, and the project uses the copies. To copy each new
import, set `paw.opt.copy_imports = true`.
