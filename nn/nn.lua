local c=require("component")
local event=require("event")
local serial=require("serialization")
local m=c.modem

local nn={}

m.setStrength(2);
m.open(1)
local dictFile="/nndict.txt"

local args={...}
local finished = (#args == 0)

nn.dict = {}
nn.activeports = {}

local invDict={}

local function doprint(text)
  if(not finished) then
    print(text)
  end
end

function nn.loadData(location)
  local file=io.open(location,"r")
  if file == nil then
    return nn.generateDict()
  end
  local t = file:read("*all")
  if t == nil or t=="" or t=="{}" then 
    return nn.generateDict() 
  end
  t=serial.unserialize(t)
  return t
end

function nn.saveData(data,location)
  local file=io.open(location,"w")
  file:write(serial.serialize(data))
  file:close()
end

local function copy(tbl)
  return {table.unpack(tbl)}
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
  local loop=1
  while loop<5 do
    local respdata = {event.pull(2,"modem_message")}
    if respdata[6]=="nanomachines" then
      for i=1,6,1 do
        table.remove(respdata,1)
      end
      return respdata
    else
      loop = loop + 1
      if(respdata==nil) then
        doprint("Conn error")
      end
    end
  end
  return nil
end

function nn.send(command, ...)
  local resp=nil
  local loop = 0
  while resp==nil and loop<10 do
    m.broadcast(1,"nanomachines",command,...)
    resp = nn.listenForNano()
    loop=loop+1
  end
  return resp
end

function nn.clearActive()
  local resp="ClearingInputs:"
  for i,v in pairs(nn.activeports) do
    resp=resp.."\nInput: "..i.." "..v.." off"
    nn.send("setInput",v,false)
  end
  nn.activeports={}
  return resp
end

local function findEffect(tmpDict,code)
    local resp = nn.send("getActiveEffects")
    if resp[2]=="{}" or resp[2]=="" then
      return tmpDict
    end
    resp=resp[2]:gsub("{","{\"")
    resp=resp:gsub(",","\",\"")
    resp=resp:gsub("}","\"}")
    resp=serial.unserialize(resp)
    for i=1,#resp,1 do
      if tmpDict[resp[i]]==nil then
        tmpDict[resp[i]]=copy(code)
        doprint("Found: "..resp[i].." <= "..serial.serialize(code))
      end
    end
    return tmpDict
end

local function genDictRecurse(tmpDict,limit,ports,level)
  local tbl={}
  for k,v in pairs(ports) do
    tbl[k+1]=v
  end
  for j=1,limit,1 do
    tbl[1]=j
    doprint("Checking "..serial.serialize(tbl).."..")
    nn.send("setInput",j,true)
    tmpDict=findEffect(tmpDict,tbl)
    if(level < nn.safeInputs) then
      tmpDict=genDictRecurse(tmpDict,j-1,tbl,level+1)
    end
    nn.send("setInput",j,false)
  end
  return tmpDict
end
    
function nn.generateDict()
  doprint(nn.clearActive())
  doprint("\nChecking combinations:")
  local tmpDict={}
  tmpDict=genDictRecurse(tmpDict,nn.maxinput,{},1)
  nn.saveData(tmpDict,dictFile)
  return tmpDict
end

function nn.handlePlayerInfo()
  local pinfo={}
  
  resp=nn.send("getName")
  if resp[2]=="" then resp[2]="Unknown" end
  pinfo.name=resp[2]
  resp=nn.send("getAge")
  pinfo.age=tonumber(resp[2])
  resp=nn.send("getHealth")
  pinfo.health=tonumber(resp[2])
  resp=nn.send("getHunger")
  pinfo.hunger=tonumber(resp[2])
  pinfo.saturation=tonumber(resp[3])
  resp=nn.send("getExperience")
  pinfo.xp=tonumber(resp[2])
  
  setmetatable(pinfo,{
    __tostring=function(pinfo)
      return "Player Information\n"..
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
  local dictValue=nn.dict[comnum]
  if dictValue ~= nil then
    comnum=dictValue
  else
    comnum="{"..comnum.."}"
    local i=invDict[comnum]
    comnum=serial.unserialize(comnum)
    if i~=nil then
      i=serial.serialize(invDict[comnum])
      i=i:gsub("[{}]","")
    else
      i="unknown"
    end
    doprint("Effect/s: "..i)
  end
  local changes = {added=copy(comnum),removed=copy(nn.activeports)}
  for k=1,#changes.added do
    local rem=true
    while rem do
      rem=false
      v=changes.added[k]
      for p=1,#changes.removed do
        if(v==changes.removed[p]) then
          table.remove(changes.added,k)
          table.remove(changes.removed,p)
          rem=true
          break
        end
      end
    end
  end
  local doadd=#changes.added+#nn.activeports>nn.safeInputs
  if(#changes.added==0) then
    doadd=true
    changes.removed=copy(comnum)
  end
  if(doadd) then
    for k,v in pairs(changes.removed) do
      nn.send("setInput",v,false)
      for p,o in pairs(nn.activeports) do
        if(o==v) then table.remove(nn.activeports,p) end
      end
    end
  else
    changes.removed={}
  end
  for k,v in pairs(changes.added) do
    nn.send("setInput",v,true)
    table.insert(nn.activeports,v) 
  end
  return setmetatable(changes,{__tostring=function(changes)
    local resstring="Changes:"
    for _,v in pairs(changes.removed) do
      resstring=resstring.."\n Input: "..v.." Off"
    end
    for _,v in pairs(changes.added) do
      resstring=resstring.."\n Input: "..v.." On"
    end
    return resstring
  end})
end

function nn.listActiveEffects()
  local resp = nn.send("getActiveEffects")
  if(resp==nil) then
    return ""
  end
  if resp[2]=="" or resp[2]=="{}" then
    resp={}
  else
    resp=resp[2]:gsub("([^{,}]+)","\"%1\"")
    resp=serial.unserialize(resp)
  end
  local effects=setmetatable(resp,{
    __tostring=function(table)
      local tabledata=""
      for i=1,#resp do
        tabledata=tabledata.."\n"..i .. ": " .. resp[i]
      end
      if(#resp==0) then
        tabledata="\nnone"
      end
      return "Active effects:"..tabledata
    end
  })
  return effects
end

function nn.handleNanoInfo()
  local nanoInfo={}
  local resp=nn.send("getPowerState")
  nanoInfo.energy=tonumber(resp[2])
  nanoInfo.safeInputs=nn.safeInputs
  nanoInfo.maxenergy=nn.maxenergy
  nanoInfo.activeports=nn.activeports
  nanoInfo.maxinput=nn.maxinput
  resp=nn.send("getActiveEffects")
  resp = resp[2]:gsub("([^{,}]+)","\"%1\"")
  nanoInfo.effects=serial.unserialize(resp)
  
  setmetatable(nanoInfo,{
    __tostring=function(nanobot)
      return "Nanobot information:"..
      "\n Energy: "..nanobot.energy.."/"..nanobot.maxenergy..
      "\n Effects: "..#(nanobot.effects)..
      "\n Safe Inputs: "..#(nanobot.activeports).."/"..nanobot.safeInputs..
      "\n Maximum Input: "..nanobot.maxinput
    end
  })
  return nanoInfo
end

function nn.listEffects()
  local effects=nn.dict
  setmetatable(effects,{
    __tostring=function(effects)
      local effectsString=""
      for i,v in pairs(effects) do
       i=serial.serialize(i)
        i=i:gsub("[{}]","")
        effectsString=effectsString.."\n"..i..": "..serial.serialize(v)
      end
      return "All effects:"..effectsString
    end
  })
  return effects
end

function nn.addEffect(input,Effect)
  if(input==nil) then
    doprint("Add effect:")
    while input==nil do
      io.write("Insert Effect Input/s: ")
      input = io.read()
      if input == "q" then return false end
      local exclusion =input:find("[^%d,]")
      if(nn.dict[input]) then 
        input=nn.dict[input] 
      elseif exclusion ~= nil then 
        doprint("Effect Input must be number, existing element or number list (q to quit)")
      else
        input="{"..input.."}"
        input=serial.unserialize(input)
      end
    end
  end
  if(Effect == nil) then
    Effect=""
    while #Effect < 2 do
      io.write("Insert Effect Name: ")
      Effect = io.read()
      if Effect == "q" then return false end
      if #Effect < 2 then
        doprint("Effect Name must be longer than 2 characters (q to quit)")
      elseif nn.dict[Effect]~= nil then
        doprint("Effect name already used (q to quit)")
        Effect = ""
      end
    end
  end
  nn.dict[Effect]=input
  invDict=invertDict(nn.dict)
  nn.saveData(nn.dict,dictFile)
  return "Effect "..Effect.." added. Inputs: "..serial.serialize(input)
end

function nn.removeEffect(Effect)
  if(Effect==nil) then
    doprint("Remove effect:")
    while Effect == nil do
      io.write("Insert Effect Name: ")
      Effect = io.read()
      if Effect == "q" then return nil end
      if nn.dict[Effect]== nil then
        doprint("Effect name not used (q to quit)")
        Effect = nil
      end
    end
  end
  nn.dict[Effect]=nil
  invDict=invertDict(nn.dict)
  nn.saveData(nn.dict,dictFile)
  return "Effect "..Effect.." removed"
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

function nn.init(port)
  if port==nil then
    port=1
  end
  nn.send("setResponsePort",port)
  doprint("Getting nanomachine data")
  resp=nn.send("getTotalInputCount")
  nn.maxinput=tonumber(resp[2])
  doprint("\tMaximum Input: "..resp[2])
  resp=nn.send("getSafeActiveInputs")
  nn.safeInputs=tonumber(resp[2])
  doprint("\tSafeInputs: "..resp[2])
  resp=nn.send("getPowerState")
  nn.maxenergy=tonumber(resp[3])
  doprint("\tMax Energy: "..resp[3])

  doprint("\nGetting active ports")
  for i=1,nn.maxinput,1 do
    resp=nn.send("getInput",i)
    if(resp[3]) then
      nn.activeports[#nn.activeports+1]=i
      doprint("Port: "..i.." on")
    elseif(i%5==0) then
      doprint(i.." Scanned")
    end
  end
  
  doprint("\nPreparing dictionary")
  nn.dict=nn.loadData(dictFile)
  invDict=invertDict(nn.dict)
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
  __index = function(_,command)
    local exclusion=command:find("[^%d,]")
    local res="Unknown command"
    if exclusion == nil or nn.dict[command] then
      res=nn.switchInput(command)
    end
    return function() return res end
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
  return nn
end
if(args[1]~="cmd") then
  nn.init()
  for i=1,#args do
    print((funcList[args[i]])())
  end
  finished=true
  return nn
end
nn.init()
while not finished do
  finished=readNext()
end