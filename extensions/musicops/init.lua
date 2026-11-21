-- musicops: the edits a musician makes to notes all day, as operators under
-- `gz` (humanize, strum, arpeggiate, quantize, crescendo, transpose in the
-- key, ...), phrase and chord text objects, and the project's key. The
-- functions themselves are in `require("musicops")`. See README.md.
local define = paw.option.define

define("musicops_seed", nil)                -- fixed seed for `gzh`; nil: a new one each time
define("musicops_humanize_timing", 0.02)    -- beats either way
define("musicops_humanize_velocity", 8)     -- velocity either way
define("musicops_humanize_length", 0)       -- fraction of the length either way
define("musicops_strum", 0.05)              -- beats between the strings of a strum
define("musicops_arp_step", nil)            -- beats between arpeggio notes; nil: the piano roll's grid
define("musicops_arp_gate", 1)              -- arpeggio notes' length, in steps
define("musicops_legato_gap", 0)            -- beats left between notes by `gzl`
define("musicops_staccato", 0.5)            -- `gzt` keeps this much of each note
define("musicops_strength", 1)              -- how far `gzq` moves notes to the grid, 0 to 1
define("musicops_swing", 0)                 -- swing of `gzq`, as a fraction of a grid step
define("musicops_swing_amount", 1 / 3)      -- swing of `gzw`; 1/3 is triplet swing
define("musicops_ramp", 30)                 -- velocity added (or taken) by the end of a crescendo
define("musicops_compress", 0.5)            -- `gzc` brings velocities this far to the average
define("musicops_accent", 20)               -- velocity `gze` adds on the beat
define("musicops_together", 1 / 16)         -- notes starting this close (beats) are one chord
define("musicops_snap", "nearest")          -- where off-key notes go: nearest, up, down
define("musicops_mirror_chromatic", false)  -- `gzm` mirrors in semitones rather than in the key
define("musicops_scale_lock", false)        -- note entry and <C-a> <C-x> stay in the key

local musicops = require("musicops")
musicops.keys = require("musicops.keys")
