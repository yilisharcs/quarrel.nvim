# quarrel.nvim

## entr

> File watch utils

**OPTIONS**
* doc
    * flags: -d --doc
    * desc: Live inspect the generated documentation

* json
    * flags: -j --json
    * desc: Live inspect the arglist database

```nu
if not ($env.doc? | is-empty) {
    fd \.lua | entr -cs "mask doc"
} else if not ($env.json? | is-empty) {
    cd ~/.local/share/nvim/quarrel
    fd arglists.msgpack | entr -cs "nu -c 'open arglists.msgpack | to json | jq'"
}

```
