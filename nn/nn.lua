local c=require("component")
local event=require("event")
local serial=require("serialization")
local m=c.modem

m.setStrength(2);
m.open(1)
local dictFile="dict.txt"

local dict = {}
local activeports = {}

local function loadData(location)
  local file=io.open(location,"r")
  if file == nil then return nil end
  local t = file:read("*all")
  t = serial.unserialize(t)
  if t == nil then return nil end
  return t
end

local function saveData(data,location)
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

local posdict=loadData(dictFile)


local function listenForNano()
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
      print("Conn error; retrying")
    end
  end
  return nil
end

local function send(command, ...)
  m.broadcast(1,"nanomachines",command,...)
  local resp = listenForNano()
  return resp
end

print("Getting nanomachine data")
  resp=send("getTotalInputCount") or 1
  local maxinput=resp[2]
  print("\tMaximum Input: "..resp[2])
  resp=send("getSafeActiveInputs")
  local safeInputs=resp[2]
  print("\tSafeInputs: ",resp[2])

local function clearActive()
  for i,v in pairs(activeports) do
    print("Input: ",i,v," off")
    send("setInput",v,false)
  end
  active={}
end

local function addEffect(code)
    local resp = send("getActiveEffects")
    if resp[2]=="{}" or resp[2]=="" then
      return
    end
    resp=resp[2]:gsub("{","{\"")
    resp=resp:gsub(",","\",\"")
    resp=resp:gsub("}","\"}")
    resp=serial.unserialize(resp)
    for i=1,#resp,1 do
      if(not dict[resp[i]]) then
        dict[resp[i]]=code
        print("Found: ",resp[i]," <= ",serial.serialize(code))
      end
    end
end

local function genDictRecurse(limit,ports,level)
  local tbl={}
  for k,v in pairs(ports) do
    tbl[k+1]=val
  end
  for j=0,limit,1 do
    if(#ports~=0)then
    if(0==j) then
      print("Checking ",serial.serialise(ports),"..")
      addEffect(ports)
    else
      tbl[1]=j
      print("Checking ",serial.serialise(tbl),"..")
      send("setInput",j,true)
      addEffect(tbl)
      if(level < safeInputs) then
        genDictRecurse(j-1,tbl,level+1)
      end
      send("setInput",j,false)     
    end
    end
  end
end
    

local function generateDict()
  print("Clearing inputs")
  clearActive()
  print("\nChecking combinations")
  genDictRecurse(maxinput,{},1)
  savedata(dict,dictfile)
end


print("\nGetting active ports")
for i=1,maxinput,1 do
  resp=send("getInput",i)
  if(resp[3]) then
    activeports[#activeports+1]=i
    print("Port: ",i," on")
  else if(i%5==0) then
    print(i," Scanned")
  end end
end

print("\nPreparing dictionary")
if posdict~=generateDict() then dict = posdict end

local invDict=invertDict(dict)

local function handlePlayerInfo()
  print("Player Information")
  resp=send("getName")
  if resp[2]=="" then resp[2]="Unknown" end
  print(resp[2]..":")
  resp=send("getAge")
  print("  Age:      "..resp[2])
  resp=send("getHealth")
  print("  Health:   "..resp[2])
  resp=send("getHunger")
  print("  Hunger:   "..resp[2])
  print("  Saturation: "..resp[3])
  resp=send("getExperience")
  print("  Exp:      "..resp[2].."\n")
end

local function switchInput(comnum)
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
  local toAdd=comnum
  local toRemove=activeports
  for k,v in pairs(toAdd) do
    for p,o in pairs(toRemove) do
      if(v==o) then
        table.remove(toAdd,k)
        table.remove(toRemove,p)
      end
    end 
  end
  if(#toAdd==0) then
    print("Already active")
  end
  if(#toAdd+#activeports>safeInputs) then
    for k,v in pairs(toRemove) do
      print("Input: ",v," off")
      send("setInput",v,false)
      for p,o in pairs(activeports) do
        if(o==v) then table.remove(activeports,p) end
      end
    end
  end
  for k,v in pairs(toAdd) do
    print("Input: ",v," on")
    send("setInput",v,true)
    table.insert(activeports,v) 
  end
  local com=""
  if resp then
    com="off"
  else
    com="on"
  end
  print("Input: ",comnum," ",com,"\n")
end

local function listActiveEffects()
  print("Active effects:")
  local resp = send("getActiveEffects")
  if resp[2]=="{}" or resp[2]=="" then
    print("none")
    return false
  end
  resp=resp[2]:gsub("([^{,}]+)","\"%1\"")
  resp=serial.unserialize(resp)
  for i=1,#resp,1 do
    print(i .. ": " .. resp[i] .. "\n")
  end
  return false
end

local function checkInput(comnum)
  local resp=send("getInput",comnum)
  resp = resp[3]
  local com=""
  if resp then
    com="off"
  else
    com="on"
  end
  print("Input: ",comnum," ",com,"\n")
end

local function handleNanoInfo()
  print("Nanobot information:")
  local resp=send("getPowerState")
  print("\tEnergy: ",resp[2].."/"..resp[3])
  resp=send("getActiveEffects")
  local _,count = string.gsub(resp[2],",","")
  if resp[2]~="{}" then
    count=count+1 --for first value
  end
  print("\tEffects: "..count)
  print("\tSafeInputs: ",#activeports.."/"..safeInputs)
  print("\tMaximum Input: "..maxinput)
  return false
end

function listEffects()
  print("All effects:")
  local index=1
  for k,i in pairs(dict) do
    i=serial.serialize(i)
    i=i:gsub("[{}]","")
    io.write(k..": "..i.." \t")
    if index % 4 == 0 then
      io.write("\n")
    end
    index=index+1
  end
  io.write("\n")
  return false
end

local function addEffect()
  print("Add effect:")
  local input=nil
  while input==nil do
    io.write("Insert Effect Input: ")
    input = io.read()
    if input == "q" then return false end
    local exclusion =input:find("[^%n,]")
    if(dict[input]) then 
      input=dict[input] 
    elseif exclusion ~= nil then 
      print("Effect Input must be number, existing element or number list (q to quit)")
    else
      input="{"..input.."}"
      input=serial.unserialize(input)
    end
    
  end
  local Effect = ""
  while #Effect < 2 do
    io.write("Insert Effect Name: ")
    Effect = io.read()
    if Effect == "q" then return false end
    if #Effect < 2 then print("Effect Name must be longer than 2 characters (q to quit)") end
    if dict[Effect]~= nil then
      print("Effect name already used (q to quit)")
      Effect = ""
    end
  end
  dict[Effect]=input
  invDict=invertDict(dict)
  saveData(dict,dictFile)
  return false
end

local function removeEffect()
  print("Remove effect:")
  local Effect = nil
  while Effect == nil do
    io.write("Insert Effect Name: ")
    Effect = io.read()
    if Effect == "q" then return nil end
    if dict[Effect]== nil then
      print("Effect name not used (q to quit)")
      Effect = nil
    end
  end
  dict[Effect]=nil
  invDict=invertDict(dict)
  saveData(dict,dictFile)
  return false
end

local function commands()
  print("Nanomachine Help menu:")
  print("Standard Commands:")
  print(" p | player: Get data about player")
  print(" q | quit:   Stop program")
  print(" l | list:   Get list of saved effects and Inputs")
  print(" a | active: Get active effects")
  print(" n | nano:   Get data about nanomachines")
  print(" + | add:    Link effect to Input")
  print(" - | remove: Remove effect link")
  print(" h | help:   Show this menu")
  print("\nInputs:")
  print(" 1-Max_input: enables/disables Input number given")
  print(" effect_name: enables/disables Input linked to effect")
  return false
end

local q() do 
  print("quit") 
  return true
end

local funcList = setmetatable({
  p = handlePlayerInfo, player = handlePlayerInfo,
  q = q, quit = q,
  l = listEffects, list = listEffects,
  a = listActiveEffects, active = listActiveEffects,
  n = handleNanoInfo, nano = handleNanoInfo
  + = addEffect, add = addEffect,
  - = removeEffect, remove = removeEffect,
  h = commands, help = commands,
  c = clearActive, clear = clearActive, none = clearActive
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
    return func()
  end
  return false
end

local finished = false
while not finished do
  finished=readNext()
end