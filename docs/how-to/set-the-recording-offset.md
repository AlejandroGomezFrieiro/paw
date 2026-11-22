# How to set the recording offset

You can make recordings line up with the song by setting the recording
offset. paw moves each take earlier by the latency that the audio system
reports, but some latency is not reported, and the recording offset
corrects it. The rule is in
[Recording](../reference/recording.md#recording-offset).

1. Record the metronome through your interface:
   1. Plug an output of your interface into an input with a cable.
   2. Select a track and set its input to that input channel with `I`.
   3. Enable the metronome, and record some bars of the metronome on the
      track.
2. Zoom in on the start of a bar, and measure the time from the bar line
   to the first click in the recording, in milliseconds.
3. In `init.lua`, set the offset to that time:

   ```lua
   paw.transport.record_offset = 4.5
   ```

4. Start paw again and record the metronome again. The clicks now start on
   the bar lines.

If the clicks are early, use a smaller value. The offset can be negative.
