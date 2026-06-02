
# x-chip-deb-repo

## details

This repo will rebuild the debian repo in pages every time this job is triggered.
That's mostly to account for github pages size limitations.

## instrumentation

```
$ curl -fsSL https://nextthingco.github.io/x-chip-deb-repo/trixie/public.key \
  | sudo tee /usr/share/keyrings/chip.asc >/dev/null
$ echo 'deb [signed-by=/usr/share/keyrings/chip.asc] https://nextthingco.github.io/x-chip-deb-repo/trixie trixie main' \
  | sudo tee /etc/apt/sources.list.d/chip.list
```
