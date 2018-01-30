This is a simple implementation of a Twofish-256 CTR stream cipher. It uses Lua 5.3(ish) and lsx. This is in the public domain.

Get Lua 5.3(ish) the usual way for your platform. If you have luarocks, you can install lsx with: `luarocks install lualsx`. If you don't, the recommended way to install lsx is to install luarocks and use that to install lsx. :)

It's a bit clunky, so I included a semi-portable shell script that can be included in pipelines and (so long as stderr is a terminal) interactively prompts for details of the encryption. (Putting such details into command lines is bad.)
