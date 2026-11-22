# How to sign in to TONE3000 from paw

<!-- tags: tone3000-login tone3000-sign-in tone3000-token tone3000-live-tests -->

You can sign in to your TONE3000 account from paw, so that paw can
download the models that you choose in TONE3000's library. The page also
shows how to run the live tests of TONE3000. The steps assume that you
have a TONE3000 account and that the
[plugstate](../../extensions/plugstate/README.md) extension is loaded
(`:ext.load plugstate`).

## Get a `client_id` from TONE3000

paw signs in as an app of your account, and TONE3000 identifies the app by
its publishable key, which the API calls the `client_id`.

1. Open <https://www.tone3000.com/settings> and sign in.
2. Find the keys of the API, and make the keys of an app if you do not
   have them. TONE3000 gives a publishable key and a secret key.
3. Copy the publishable key, which is the only key that paw needs. Do not
   give the secret key to paw, and do not put it in a file that other
   people can read.

paw signs in with the device flow, so the app needs no redirect address.
paw asks for the `read` scope, which is the scope that TONE3000 gives by
default.

## Give the `client_id` to paw

Put the following line in `~/.config/paw/init.lua`:

```lua
paw.opt.plugstate_tone3000_client_id = "<your publishable key>"
```

Or set the environment variable `TONE3000_CLIENT_ID` before you start paw.
The publishable key is not a secret, because TONE3000 makes it for apps
that everybody can read.

## Sign in

1. Type `:plugstate.tone3000_login` and press `Enter`. A float shows a
   code, for example `BCDF-GHJK`, and the address
   `https://www.tone3000.com/activate`.
2. On a phone or a computer, open the address and enter the code. If you
   are not signed in to TONE3000 there, sign in first.
3. Press `q` or `Esc` to close the float, and go on with your work, while
   paw asks TONE3000 in the background. After you enter the code,
   the message line shows `TONE3000: signed in as <your name>`.

The code expires after 10 minutes. If it expires, type
`:plugstate.tone3000_login` again for a new code. If you decline the
sign-in on TONE3000, paw stops and changes nothing.

paw keeps the tokens in the keyring, through `secret-tool`. If there is no
keyring, paw keeps them in `$XDG_STATE_HOME/paw/tone3000-session.json`,
a file that only you can read (mode 600). The tokens are never in a
project, a log or a message. When the access token expires, paw gets a new
one with the refresh token.

## Look at the sign-in, or sign out

- To see if you are signed in, and when the access token expires, type
  `:plugstate.tone3000_status`.
- To sign out, type `:plugstate.tone3000_logout`, and paw removes the
  tokens from the keyring and from the file.

A token in `TONE3000_TOKEN` or in the token file comes before the sign-in.
The order of all the places is in
[TONE3000 tokens](../../extensions/plugstate/README.md#tone3000-tokens).

## Run the live tests of TONE3000

The live tests search TONE3000 and read the models of one tone. Then they
download one small model and play it in Neural Amp Modeler. They make
about seven requests. They keep the model only in their scratch folder.

1. Sign in from paw, as above.
2. In the folder of paw, build paw and run the tests:

   ```sh
   nix develop -c cargo build --release -j 8
   tests/tools/live.sh tone3000
   ```

3. The last line shows `all passed`, or the number of tests that failed.
   The file `target/test-scratch/suite.out` has all the output, and the
   fields of the answers that the mock of the tests does not have.

To test the TONE3000 plugin too, set `PAW_TEST_TONE3000` to the folder of
its package before you run the tests.

If you want to use a token file in place of the sign-in, follow the steps
below:

1. Make an empty file that only you can read:

   ```sh
   install -m 600 /dev/null ~/.config/paw/tone3000-token
   ```

2. Open the file in an editor, and put an access token on its first line.
   Do not type the token on the command line, because the shell keeps a
   history. If paw keeps the sign-in in the file `tone3000-session.json`,
   the access token is its `access_token` value.
3. Run the tests with the file:

   ```sh
   TONE3000_TOKEN_FILE=~/.config/paw/tone3000-token tests/tools/live.sh tone3000
   ```

An access token expires. If the tests fail with `401`, put a new token
in the file, or use the sign-in.
