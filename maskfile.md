# quarrel.nvim

## doc

```nu
let version = "429e5f9dc9cd59bf76cd98b687300f0a384a7f52"
let url = $"https://raw.githubusercontent.com/nvim-mini/mini.nvim/($version)/lua/mini/doc.lua"
let mini_doc_checksum = "9013bd8d1386cddbb84be2cc519a86c91a583fc078e11b7f6e1c2ea323a903d8"

let dest = "tmp/mini/doc.lua"
mkdir (dirname $dest)

http get $url | save -f $dest
if (open $dest | hash sha256) != $mini_doc_checksum {
        # rm -rf tmp
        error make -u {
                msg: "Checksum mismatch"
        }
}

let args = [
        "--headless"
        "-u" "NONE"
        "-c" "lua package.path = './tmp/?.lua' .. ';' .. './tmp/?/init.lua' .. package.path"
        "-c" "lua require('mini.doc').generate({ 'lua/quarrel/init.lua', 'plugin/quarrel.lua' }, 'doc/quarrel.nvim.txt', {})"
        "-c" "qa!"
]
nvim ...$args

rm -rf tmp
```

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
