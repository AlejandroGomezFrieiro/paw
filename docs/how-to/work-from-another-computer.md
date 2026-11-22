# How to work on paw from another computer

<!-- tags: on-another-machine remote -->

You can connect a terminal or a graphical window to a paw instance on
another computer. On the page, `studio` is the computer that runs the
instance, and the other computer is the client.

## Connect over the network

1. On `studio`, start the instance with `--listen-tcp`:

   ```sh
   paw --listen-tcp 0.0.0.0:7700
   ```

   To accept connections only from `studio` itself, use `127.0.0.1:7700`.
   To start it without a terminal interface, add `--headless`.
2. Find the fingerprint in the start message: `listening on … certificate 9f1c:…`.
3. Copy `~/.local/state/paw/token` from `studio` to the client, for example as `studio.token`.
4. On the client, connect a terminal or a graphical window, and at the
   first connection, compare the fingerprint that the client shows with
   the fingerprint from step 2:

   ```sh
   paw attach --connect studio:7700 --token-file studio.token
   ```

   ```sh
   paw-gui --connect studio:7700 --token-file studio.token
   ```

If the client refuses the certificate after an earlier connection, either
the instance has a new certificate, or a different computer answers. If
you know that the instance made a new certificate, add
`--accept-certificate`.

On a network that you trust, you can use no encryption by adding
`--no-tls` to the instance and to each client.

## Connect through SSH

You can connect through an SSH tunnel to the socket of the instance, and
the instance needs no option for it.

```sh
ssh -N -L /tmp/studio.sock:/run/user/1000/paw.sock studio &
paw attach --socket /tmp/studio.sock
```

## Import a sound file from the client

Import and Open show the files of `studio`. To import a sound file from
the client, do one of the following:

- Drop the file on a graphical window that is connected to `studio`, or
  choose the file in the Import dialog of a connected graphical window.
- Type `:upload ~/take.wav` in a connected terminal.

paw sends the file to the `media` folder of the project on `studio`, and
it imports the file on a new track. If the project has no file yet, paw
uses a scratch folder.

## Hear the sound on the client

The sound plays on `studio`. If you also want to hear it on the client, do
one of the following:

- Start the client with `--listen-audio`.
- Type `:listen` in a connected terminal, and type it again to stop.
- In a connected graphical window, choose "Hear it on this machine" in the engine menu.

To write the sound to a file on the client, start the client with
`paw attach --listen-audio-to heard.wav`.

The sound arrives a quarter of a second late, or more, so use it to
monitor a mix and not to play with the song.

## Leave

Type `:detach` in an attached terminal, and the instance continues to run.

## See also

- [About seats](../explanation/about-seats.md): what each frontend has of its own, and why the network is safe.
- [The programs and their options](../reference/programs.md).
- [How to run the graphical window against a kernel on another machine](run-the-window-against-a-remote-kernel.md): the graphical window in more detail.
