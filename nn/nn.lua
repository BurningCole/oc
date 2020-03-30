local c=require("component")
local event=require("event")
local serial=require("serialization")
local m=c.modem

local nn={}

m.setStrength(2);
m.open(1)
local dictFile="/usr/etc/nn/dict.txt"

local args={...}
local finished = (#args ~= 0)

nn.dict = {}
nn.activeports = {}

local invDict={}

local function doprint(text)
  if(finished) then
    print(text)
  end
end

function nn.loadData(location)
  local file=io.open(location,"r")
  if file == nil 
    return generateDict()
  end
  local t = file:read("*all")
  t = serial.unserialize(t)
  if t == nil or #t==0 then 
    return generateDict() 
  end
  return t
end

function nn.saveData(data,location)
  file=io.open(location,"w")
  file:write(serial.serialize(data))
  file:close()
end

local function invertDict(d)
  invd={}
  for k,v in pairs(d) do
    v=serial.serialize(v)
    if invd[v] ~= nil then
      invd[v][#invd[v]+1]=k
    else
      invd[v]={k}
    end
  end
  return invd
end

function nn.listenForNano()
  resp=nil
  local loop=1
  while resp==nil and loop<5 do
    local respdata = {event.pull(2,"modem_message")}
    if respdata[6]=="nanomachines" then
      for i=1,6,1 do
        table.remove(respdata,1)
      end
      loop = loop + 1
      if loop>10 then break end
      return respdata
    else
      doprint("Conn error; retrying")
    end
  end
  return nil
end

function nn.send(command, ...)
  m.broadcast(1,"nanomachines",command,...)
  local resp = listenForNano()
  return resp
end

function nn.clearActive()
  local resp="ClearingInputs:"
  for i,v in pairs(activeports) do
    resp+="\nInput: "..i.." "..v.." off"
    send("setInput",v,false)
  end
  active={}
  return resp
end

local function findEffect(tmpDict,code)
    local resp = send("getActiveEffects")
    if resp[2]=="{}" or resp[2]=="" then
      return tmpDict
    end
    resp=resp[2]:gsub("{","{\"")
    resp=resp:gsub(",","\",\"")
    resp=resp:gsub("}","\"}")
    resp=serial.unserialize(resp)
    for i=1,#resp,1 do
      if(not tmpDict[resp[i]]) then
        tmpDict[resp[i]]=code
        doprint("Found: "..resp[i].." <= "..serial.serialize(code))
      end
    end
    return tmpDict
end

local function genDictRecurse(tmpDict,limit,ports,level)
  local tbl={}
  for k,v in pairs(ports) do
    tbl[k+1]=val
  end
  for j=0,limit,1 do
    if(#ports~=0)then
    if(0==j) then
      doprint("Checking "..serial.serialise(ports).."..")
      tmpDict=findEffect(tmpDict,ports)
    else
      tbl[1]=j
      doprint("Checking "..serial.serialise(tbl).."..")
      send("setInput",j,true)
      tmpDict=findEffect(tmpDict,tbl)
      if(level < safeInputs) then
        tmpDict=genDictRecurse(tmpDict,j-1,tbl,level+1)
      end
      send("setInput",j,false)     
    end
    end
  end
  return tmpDict
end
    
function nn.generateDict()
  doprint(nn.clearActive())
  doprint("\nChecking combinations:")
  local tmpDict={}
  tmpDict=genDictRecurse(tmpDict,maxinput,{},1)
  savedata(tmpDict,dictfile)
  return tmpDict
end

function nn.handlePlayerInfo()
  local pinfo={}
  
  resp=send("getName")
  if resp[2]=="" then resp[2]="Unknown" end
  pinfo.name=resp[2]
  resp=send("getAge")
  pinfo.age=resp[2]
  resp=send("getHealth")
  pinfo.health=resp[2]
  resp=send("getHunger")
  pinfo.hunger=resp[2]
  pinfo.saturation=resp[3]
  resp=send("getExperience")
  pinfo.xp=resp[2]
  
  setmetatable(pinfo,{
    __tostring=function(pinfo)
      return "Player Information"..
      pinfo.name..":"..
      "\n  Age:      ".. pinfo.age..
      "\n  Health:   "..pinfo.health..
      "\n  Hunger:   "..pinfo.hunger..
      "\n  Saturation: "..pinfo.saturation..
      "\n  Exp:      "..pinfo.xp.."\n"
    end
  })
  return pinfo
end

function nn.switchInput(comnum)
  local dictValue=dict[comnum]
  if dictValue ~= nil then
    comnum=dictValue
  else 
    i=invDict[comnum]
    if i~=nil then
      i=serial.serialize(invDict[comnum])
      i=i:gsub("[{}]","")
    else
      i="unknown"
    end
  end
  for
  local changes={added=comnum,removed=activeports}
  for k,v in pairs(changes.added) do
    for p,o in pairs(changes.removed) do
      if(v==o) then
        table.remove(changes.added,k)
        table.remove(changes.removed,p)
      end
    end 
  end
  if(#changes.added+#activeports>nn.safeInputs) then
    for k,v in pairs(changes.remove) do
      send("setInput",v,false)
      for p,o in pairs(activeports) do
        if(o==v) then table.remove(activeports,p) end
      end
    end
  else
    changes.removed={}
  end
  for k,v in pairs(changes.added) do
    send("setInput",v,true)
    table.insert(activeports,v) 
  end
  return setmetatable(changes,{__tostring=function(changes)
    local resstring="Changes:"
    for _,v in pairs(changes.removed) do
      resstring+="\n Input: "..v.." Off"
    end
    for _,v in pairs(changes.added) do
      resstring+="\n Input: "..v.." On"
    end
    return resstring
  end})
end

function nn.listActiveEffects()
  local resp = send("getActiveEffects")
  if(resp==nil) then
    return ""
  end
  if resp[2]=="" or resp[2]=="{}" then
    resp=nil
  else
    resp=resp[2]:gsub("([^{,}]+)","\"%1\"")
    resp=serial.unserialize(resp)
  end
  local effects=setmetatable(resp,{
    __tostring=function(table)
      local tabledata=""
      for i=1,#resp do
        tabledata=tabledata.."\n"..i .. ": " .. resp[i])
      end
      if(#resp==0){
        tabledata="\nnone"
      }
      return "Active effects:"..tabledata
    end
  })
  return false
end

function nn.handleNanoInfo()
  local nanoInfo={}
  local resp=send("getPowerState")
  nanoInfo.energy=resp[2]
  resp=send("getActiveEffects")
  resp = resp[2]:gsub("([^{,}]+)","\"%1\"")
  nanobot.effects=serial.unserialize(resp)
  
  setmetatable(nanoInfo,{
    __tostring=function(nanobot)
      return "Nanobot information:"..
      "\n Energy: "..nanobot.energy.."/"..nanobot.maxenergy..
      "\n Effects: "..#(nanobot.effects)..
      "\n Safe Inputs: "..#(nn.activeports).."/"..nanobot.safeInputs..
      "\n Maximum Input: "..nn.maxinput
    end
  })
  return effects
end

function nn.listEffects()
  local effects=dict
  setmetatable(effects,{
    __tostring=function(effects)
      local effectsString=""
      for i,v in pairs(effects) do
       i=serial.serialize(i)
        i=i:gsub("[{}]","")
        effectsString+="\n"..k..": "..i
      end
      return "All effects:"..effectsString
    end
  })
  return effects
end

function nn.addEffect(input,Effect)
  if(input==nil) then
    doprint("Add effect:")
    local input=nil
    while input==nil do
      io.write("Insert Effect Input: ")
      input = io.read()
      if input == "q" then return false end
      local exclusion =input:find("[^%n,]")
      if(dict[input]) then 
        input=dict[input] 
      elseif exclusion ~= nil then 
        doprint("Effect Input must be number, existing element or number list (q to quit)")
      else
        input="{"..input.."}"
        input=serial.unserialize(input)
      end
      
    end
  end
  if(Effect == nil) then
    while #Effect < 2 do
      io.write("Insert Effect Name: ")
      Effect = io.read()
      if Effect == "q" then return false end
      if #Effect < 2 then doprint("Effect Name must be longer than 2 characters (q to quit)") end
      if dict[Effect]~= nil then
        doprint("Effect name already used (q to quit)")
        Effect = ""
      end
    end
  end
  dict[Effect]=input
  invDict=invertDict(dict)
  saveData(dict,dictFile)
  return false
end

function nn.removeEffect(Effect)
  if(Effect==nil) then
    doprint("Remove effect:")
    while Effect == nil do
      io.write("Insert Effect Name: ")
      Effect = io.read()
      if Effect == "q" then return nil end
      if dict[Effect]== nil then
        doprint("Effect name not used (q to quit)")
        Effect = nil
      end
    end
  end
  dict[Effect]=nil
  invDict=invertDict(dict)
  saveData(dict,dictFile)
  return false
end

local function commands()
  return "Nanomachine Help menu:"..
  "\nStandard Commands:"..
  "\n p | player: Get data about player"..
  "\n q | quit:   Stop program"..
  "\n l | list:   Get list of saved effects and Inputs"..
  "\n a | active: Get active effects"..
  "\n n | nano:   Get data about nanomachines"..
  "\n c | clear: remove all effects"..
  "\n + | add:    Link effect to Input"..
  "\n - | remove: Remove effect link"..
  "\n h | help:   Show this menu"..
  "\n\nInputs:"..
  "\n 1-Max_input: enables Input number given"..
  "\n effect_name: enables Input linked to effect"
end

function nn.init(port,dict)

  doprint("Getting nanomachine data")
  resp=send("getTotalInputCount") or 1
  nn.maxinput=resp[2]
  doprint("\tMaximum Input: "..resp[2])
  resp=send("getSafeActiveInputs")
  nn.safeInputs=resp[2]
  doprint("\tSafeInputs: "..resp[2])
  resp=send("getPowerState")
  nn.maxenergy=resp[3]
  doprint("\Max Energy: "..resp[3])

  doprint("\nGetting active ports")
  for i=1,maxinput,1 do
    resp=send("getInput"..i)
    if(resp[3]) then
      activeports[#activeports+1]=i
      doprint("Port: "..i.." on")
    elseif(i%5==0) then
      doprint(i.." Scanned")
    end
  end
  
  doprint("\nPreparing dictionary")
  dict=loadData(dictFile)
  invDict=invertDict(dict)
end

local function q()
  return "quitting"
end

local funcList = setmetatable({
  p = nn.handlePlayerInfo, player = nn.handlePlayerInfo,
  ["q"] = q, quit = q,
  l = nn.listEffects, list = nn.listEffects,
  a = nn.listActiveEffects, active = nn.listActiveEffects,
  n = nn.handleNanoInfo, nano = nn.handleNanoInfo,
  ["+"] = nn.addEffect, add = nn.addEffect,
  ["-"] = nn.removeEffect, ["remove"] = nn.removeEffect,
  h = commands, help = commands,
  c = nn.clearActive, clear = nn.clearActive, none = nn.clearActive
},
{
  __index = function(_,index)
    local comnum=tonumber(command)
    if comnum ~= nil then
      switchInput(comnum)
    elseif dict[command] then
      switchInput(command)
    end
    return function() return false end
  end
}
)


local function readNext()
  io.write("command/effect:")
  local command=io.read()
  local func=funcList[command]
  if func ~= nil then
    local resp = func()
    print(resp)
    return (func==q)
  end
  return false
end

if(finished==true) then
  if(args[1]~="req") then
    nn.init()
    for i=1,#args do
      print((funcList[args[i]])())
    end
  end
  return nn
end
nn.init()
while not finished do
  finished=readNext()
end