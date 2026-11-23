# The chain language

The chain language is a text form of a chain of audio devices: devices in series, splits with parallel branches, modulators and checks. A person or a program can read and write it, and the crate `chain-syntax` parses, prints, formats and checks it. The language names no host, so any program that hosts devices can use it. Each host gives its kinds of device, split and modulator in a [schema](chain-schema.md), and the check reads that schema.

paw writes its schema with `paw chain schema` (see [the programs and their options](programs.md)).

The examples below use the kinds of a small example host: the devices `eq`, `compressor`, `saturation`, `gate`, `delay` and `limiter`, the splits `rack`, `layer` and `band`, and the modulators `macro` and `lfo`. A test of the crate checks that each example parses with no error, passes the check against the schema of the example host, and is already in the format that the formatter writes.

## A whole chain

```chain
chain 1 "Gtr bus"
-- the bus of the four guitars
eq #2 hp=90Hz lp=9kHz
band #8 "Tame" xover=150Hz,2.5kHz
  | Low #81
    compressor #5 ratio=4 threshold=-20dB key=@in
  | High #82 gain=-1dB
    saturation #6 drive=12dB curve=tube -- a little grit
layer #9 "Crush"
  | Dry
  | Crush gain=-12dB
    compressor #10 ratio=20 attack=0.1ms key=@2
rack #20 "Glue"
  saturation #21 drive=2dB curve=tape
  mods
    macro #31 "glue" value=40% -> #21.drive +6dB
mods
  lfo #30 sync=1/4 -> #81.gain -3dB, #9.mix +10%
checks
  latency <= 6ms
```

## Lines and indents

A chain is a text of lines. Each line holds one item: the header, a node, a branch, a `mods` or `checks` line, a modulator or a check. A line can end with a comment, and a line can hold only a comment or nothing.

The indent of a line says what it belongs to. Each step of indent is two spaces, and a tab in an indent is an error. A line goes one step under the line that holds it:

| Line | What goes one step under it |
| --- | --- |
| A node of a split kind | Branches (`|` lines), or nodes when the split has one branch, and one `mods` line |
| A branch | The nodes of the branch, in series |
| `mods` | Modulators |
| `checks` | Checks |
| A device, a modulator or a check | Nothing |

The top level holds the nodes of the chain in series, one `mods` line and one `checks` line. A split holds either branches or nodes, not both. A split with nodes and no `|` line has one branch, and a `rack` is such a split.

## Grammar

The grammar is in EBNF. The rules describe one line at a time, and the table above gives the indents.

```ebnf
chain       = header , { line } ;
header      = "chain" , version , [ name ] , { field } ;
line        = indent , ( node | branch | mods | modulator | checks | check ) , [ comment ] ;
node        = kind , [ id ] , [ name ] , { field } ;
branch      = "|" , [ branch-name ] , [ id ] , { field } ;
mods        = "mods" ;
modulator   = kind , [ id ] , [ name ] , { field } , [ "->" , link , { "," , link } ] ;
link        = target , value ;
checks      = "checks" ;
check       = value , { value } , compare , value , [ "+-" , value ] ;
field       = key , "=" , value , { "," , value } ;
kind        = word | quoted ;
key         = word | quoted ;
name        = quoted ;
branch-name = word | quoted ;
id          = "#" , id-char , { id-char } ;
target      = id , "." , key ;
value       = number | note | word | quoted | reference ;
number      = [ "+" | "-" ] , digit , { digit } , [ "." , digit , { digit } ] , [ unit ] ;
unit        = "dB" | "Hz" | "kHz" | "ms" | "s" | "%" | "st" ;
note        = digit , { digit } , "/" , digit , { digit } , [ "." | "t" ] ;
reference   = "@" , id-char , { id-char } ;
compare     = "<" | "<=" | "=" | ">=" | ">" ;
word        = letter , { letter | digit | "_" | "." | ":" | "/" | "+" | "-" } ;
quoted      = '"' , { character | escape } , '"' ;
comment     = "--" , { character } ;
```

`version` is the number 1. `id-char` is a letter, a digit, `_` or `-`. `letter` is any letter of any script, or `_`. `indent` is two spaces for each step. `escape` is one of `\"`, `\\`, `\n`, `\t` and `\u{hex}`, where `hex` is the number of a Unicode character in hexadecimal. Spaces separate the tokens of a line, and a line ends at its newline.

## Rules and examples

### `chain`

A chain is its header and then its lines. The top level is the chain in series, from its input to its output.

```chain
chain 1
eq #1 hp=80Hz
compressor #2 threshold=-24dB
```

### `header`

The first line that is not a comment is the header. It gives the version of the language, `1`, and it can give a name and fields. The check does not read the name and the fields of the header: the host gives them a meaning.

```chain
chain 1 "Lead vocal" rev="8f3a1c"
eq #1
```

### `line`

Each line after the header is one item, at its indent. A comment can end any line, and a line can hold only a comment. An empty line separates groups of lines, and it means nothing.

```chain
chain 1
-- the cleanup
eq #1 hp=80Hz -- below the voice

compressor #2
```

### `node`

A node is a device or a split. It starts with its kind, then its id, its name and its fields. The schema of the host says which kinds are splits.

```chain
chain 1
compressor #4 "Glue" threshold=-30dB attack=30ms
```

A node with no id is new. A host gives it an id when it applies the text. A field that a line does not name keeps the default of its parameter.

```chain
chain 1
compressor
```

### `branch`

A branch starts with `|` and goes one step under its split. It can have a name, an id and fields, and its nodes go one step under it. A branch with no nodes passes the signal on as it is.

```chain
chain 1
layer #1 "Parallel"
  | Dry
  | Crush #12 gain=-9dB
    compressor #2 ratio=20
    saturation #3 drive=18dB
```

### `mods`

`mods` holds the modulators of the split above it, or of the whole chain at the top level. A link of a modulator reaches only the nodes and branches inside its container.

```chain
chain 1
rack #1 "Glue"
  compressor #2
  mods
    macro #3 value=50% -> #2.threshold -12dB
```

### `modulator`

A modulator is a source of change: a macro, an LFO, or another kind of the host. It has a kind, an id, a name and fields, as a node has, and then its links after `->`.

```chain
chain 1
saturation #1
mods
  lfo #2 "wobble" rate=0.5Hz shape=triangle -> #1.drive +3dB
```

### `link`

A link names a parameter of a node and the depth of the change. The depth has the unit of the parameter, or `%` of its range, and a `+` or `-` sign. Commas separate the links of one modulator.

```chain
chain 1
compressor #1
saturation #2
mods
  macro #3 "push" -> #1.threshold -6dB, #2.drive +20%
```

### `checks`

`checks` holds claims about the sound of the chain, which a host can measure. It goes at the top level, after the chain.

```chain
chain 1
limiter #1 ceiling=-1dB
checks
  peak <= -1dB
```

### `check`

A check names what it measures, then a comparison and a value, and then the tolerance after `+-`. The language reads checks, and the host measures them.

```chain
chain 1
eq #1
checks
  latency <= 6ms
  gain pink -20dB = 0dB +- 1dB
```

### `field`

A field is a key, `=` and a value. Commas between values make a list. The key and the value have no spaces around the `=`.

```chain
chain 1
band #1 xover=120Hz,2kHz
  | Low
  | Mid
  | High
```

### `kind`

A kind is a word, or a quoted text when it has a character that a word cannot have. Kinds come from the host. A host can name the kinds of a plugin format with a prefix, such as `clap:`, and its schema can let such a kind be missing: the check then gives a warning, and the fields stay as they are written.

```chain
chain 1
"clap:com.example.big comp" #1
clap:com.example.sat #2 drive=9dB
```

### `key`

A key is a word, or a quoted text. A plugin often names its parameters with spaces.

```chain
chain 1
clap:com.example.amp #1 "Input gain"=6dB b1.freq=120Hz
```

### `name`

The name of a node or a modulator is a quoted text, so that it never reads as a kind.

```chain
chain 1
saturation #1 "Fizz \"top\""
```

### `branch-name`

The name of a branch is a word, or a quoted text.

```chain
chain 1
layer #1
  | Close
  | "Far room"
```

### `id`

An id names an item, so that a link or a reference can reach it. Two items cannot have one id, and the id `in` is kept for `@in`.

```chain
chain 1
eq #pre-1
compressor #2b
```

### `target`

A target is the id of a node or a branch, a `.` and the key of a parameter. Targets are the start of each link.

```chain
chain 1
layer #1
  | Wet #11
    saturation #12
mods
  macro #2 -> #11.gain -6dB, #12.drive +3dB
```

### `value`

A value is a number, a note value, a word, a quoted text or a reference. A word and a quoted text are the same value: `tube` and `"tube"` are equal, and the formatter writes the quotes only when a word cannot stand.

```chain
chain 1
delay #1 time=1/8. feedback=40% pingpong=on
saturation #2 curve=tube
```

### `number`

A number has digits, a point and more digits when it has a fraction, and a unit when its parameter has one. A parameter with a unit takes a number with a unit of the same kind, and a parameter with no unit takes a number with no unit.

```chain
chain 1
compressor #1 threshold=-18.5dB ratio=4 attack=0.3ms
```

### `unit`

| Unit | Measures | Notes |
| --- | --- | --- |
| `dB` | Gain | |
| `Hz` | Frequency | The formatter writes 1000 Hz and more in `kHz`. |
| `kHz` | Frequency | A thousand hertz. |
| `ms` | Time | The formatter writes times under a second in `ms`. |
| `s` | Time | |
| `%` | A share of a range | |
| `st` | Pitch | Semitones. |

A number keeps its value in hertz and in seconds, so `2500Hz` and `2.5kHz` are the same value. The formatter writes `2.5kHz`.

```chain
chain 1
eq #1 hp=40Hz lp=12.5kHz
delay #2 feedback=25%
```

### `note`

A note value is a count, `/` and a division: `1/4` is a quarter note. A `.` after it makes it dotted, and a `t` makes it a triplet.

```chain
chain 1
delay #1 time=3/16
mods
  lfo #2 sync=1/8t
```

### `reference`

A reference names the output of a node with `@` and its id: a compressor can listen to a node before it. `@in` is the input of the chain. A reference to the node itself, or to a node that comes later in the signal, is an error. The signal meets the nodes from the top to the bottom, and each branch of a split from its first node to its last.

```chain
chain 1
eq #1
saturation #2
gate #3 key=@in
compressor #4 key=@1
```

### `compare`

A check compares with `<`, `<=`, `=`, `>=` or `>`.

```chain
chain 1
limiter #1
checks
  peak < 0dB
  latency >= 0ms
```

### `word`

A word starts with a letter and goes on with letters, digits and the characters `_ . : / + -`. A value that is not a word, such as a text with a space, is quoted.

```chain
chain 1
saturation #1 curve=tape
clap:org.example.amp-2 #2
```

### `quoted`

A quoted text is in double quotes. The escapes `\"`, `\\`, `\n`, `\t` and `\u{hex}` write a quote, a backslash, a new line, a tab and any character.

```chain
chain 1
compressor #1 "Vocal \"glue\"" key="Lead vox"
```

### `comment`

A comment starts with `--` and goes to the end of the line. The formatter keeps each comment at its place.

```chain
-- a comment can come before the header
chain 1
eq #1 -- at the end of a line
```

## The format

The formatter writes the one layout of a chain, and it never changes what the text means:

- two spaces for each step of indent, and one space between tokens;
- each number in the unit that fits its size, such as `4kHz` for `4000Hz`;
- quotes only where a word cannot stand, and always around the name of a node;
- one empty line where the text had one or more;
- each comment, at the place of the item after it.

With the schema of the host, the formatter also writes the fields of each line in the order of the schema, and it leaves out each field at its default. A text with an error stays as it is.

## Diagnostics

A diagnostic gives the line and the column of the problem, its code, and a message. The parser goes on after an error, so one pass finds each error of the text. A text with an error changes nothing in the host. A warning does not stop the text.

| Code | Severity | Problem |
| --- | --- | --- |
| `E101` | Error | The text does not start with the line `chain 1`. |
| `E102` | Error | The header names a version of the language that the reader does not know. |
| `E103` | Error | A tab in the indent of a line. |
| `E104` | Error | An indent that is not a whole number of steps of two spaces. |
| `E105` | Error | A line more than one step deeper than the line that holds it. |
| `E106` | Error | A character or a token that the line cannot have at its place. |
| `E107` | Error | A number with a unit that the language does not have. |
| `E108` | Error | A quoted text with no closing quote, or a bad escape. |
| `E109` | Error | A line at a place where its kind of line cannot go. |
| `E201` | Error | A kind that the schema does not have. |
| `E202` | Error | A parameter that the kind does not have. |
| `E203` | Error | A value of the wrong type for its parameter. |
| `E204` | Error | A number with the wrong unit for its parameter. |
| `E205` | Error | A number out of the range of its parameter. |
| `E206` | Error | Two items with one id, or the id `in`. |
| `E207` | Error | One parameter twice on one line. |
| `E208` | Error | A split with a number of branches that its kind does not take. |
| `E209` | Error | A device with nodes under it. Only a split holds nodes. |
| `E210` | Error | A reference to no node, to the node itself, or to a later node. |
| `E211` | Error | A link to no node of its container, or to a parameter that the node does not have or that is not a number. |
| `E212` | Error | A list with the wrong count of values, or out of order. |
| `W301` | Warning | A kind with an open prefix that the schema does not have, such as a plugin that is not installed. |

A diagnostic looks like this:

```text
3:24: error E204: `ratio` takes a number with no unit, not `40kHz`
```
