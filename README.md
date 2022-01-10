# Yury Ershov's reaper64 tools and effects

## Effects

### Transient Controller mod

https://youtu.be/twKTY5g27fE

### Automatic Gain Control (AGC)

https://youtu.be/hPcTy4PMVwg

https://youtu.be/fb0ikjAVGkQ

### Phase-corrected "Simple 1-Pole Filter" for better highpass filtering.

## Tools

### Embed presets in JSFX source

* `make_rpl_all`

### JSFX (eel2) static checker

You'll need two files: `jsfx_check.pl` and `jsfx_check`.

To check a set of files, use

```bash
jsfx_check [files...]
```

To check a set of files as a single script, do

```bash
jsfx_check.pl [files...]
```

