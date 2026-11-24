# How to run the graphical window against a kernel on another machine

You can control a paw kernel on another machine with the graphical window
on your machine. On the page, the other machine is `studio`, and the steps
assume that paw is installed on the two machines.

## Start the kernel

1. On `studio`, start paw with a TCP address:

   ```sh
   paw --headless --listen-tcp 0.0.0.0:7700
   ```

   To use only the local network of one interface, give its address in
   place of `0.0.0.0`.
2. Note the fingerprint that paw shows when it starts
   (`listening on … certificate 9f1c:…`).
3. Copy the token in `~/.local/state/paw/token` on `studio` to a file on
   your machine, for example `studio.token`.

## Connect the window

1. On your machine, start the window:

   ```sh
   paw-gui --connect studio:7700 --token-file studio.token
   ```

2. Compare the fingerprint that the window remembers in
   `~/.local/state/paw/known_instances` with the fingerprint of step 2.

If the window refuses a different certificate, find the cause first. If
`studio` made a new certificate, because its state directory is lost or
paw moved to a new machine, add `--accept-certificate`. In any other case,
do not connect, because a different machine can pretend to be `studio`.

## Use SSH in place of TLS

If you can sign in to `studio` with SSH, you do not need `--listen-tcp`:

1. On `studio`, start paw: `paw --headless`.
2. On your machine, forward the socket:

   ```sh
   ssh -N -L /tmp/studio.sock:/run/user/1000/paw.sock studio &
   ```

3. Start the window on the forwarded socket:

   ```sh
   paw-gui --socket /tmp/studio.sock
   ```

## Hear the sound on your machine

The sound plays on `studio`. If you also want to hear it on your machine,
do one of the following:

- Add `--listen-audio` to the `paw-gui` command.
- In the engine menu, click "Hear it on this machine".

The sound comes 0.25 seconds late or more, and it uses about 1 Mbit/s.
Use it to monitor a mix and not to play along.

## Import a sound file from your machine

Open, Save and Render use the disk of `studio`. To import a sound file
from your disk, do one of the following:

- Drag the file from your file manager into the window (on X11).
- Use File → Import…, where the desktop's file dialog shows your disk.

The window sends the file into the media folder of the project on
`studio`, and then paw imports it on a new part.

## Related

- [The graphical window](../reference/window.md#command-line): all options of `paw-gui`.
- [The control protocol](../reference/protocol.md#connections): the token, TLS and the certificates.
- [Seats](../reference/protocol.md#seats): what each attached window has of its own.
