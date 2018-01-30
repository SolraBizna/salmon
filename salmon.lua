#!/usr/bin/env lua5.3

local lsx = require "lsx"

if #arg ~= 1 then
   io.stderr:write[[
Usage: salmon <paramfile>

paramfile must contain the 256-bit key, in hex, followed directly by the 128-bit nonce, also in hex. Only the first 96 bytes are read. It's good practice to delete it as soon as you have launched salmon, so that others can't read it.
]]
   os.exit(1)
end

local nonce, twofish
do
   local paramf = assert(io.open(arg[1], "rb"))
   local params = assert(paramf:read(96), "parameter file was bad")
   assert(#params >= 96)
   params = params:gsub("..", function(x)
                           return assert(tonumber(x,16),
                                         "parameter file was bad")
   end)
   twofish = lsx.twofish(params:sub(1,32))
   nonce = params:sub(33,48)
   paramf:close()
end

local BLOCK_SIZE = 8192
local counter = 0
collectgarbage "stop"
repeat
   collectgarbage "collect"
   local i = io.stdin:read(BLOCK_SIZE)
   if not i then break end
   while #i < BLOCK_SIZE do
      local moar,e = io.stdin:read(BLOCK_SIZE - #i)
      if e then error("while reading: "..e) end
      if moar then
         i = i .. moar
      else
         break -- EOF
      end
   end
   local ot = {}
   for start=1,#i,16 do
      ot[#ot+1] = twofish:ctr(counter, nonce, i, start)
      counter = counter + 1
   end
   assert(io.stdout:write(table.concat(ot)))
until false
