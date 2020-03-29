preenergy = 0
computer=require("computer")
maxenergy=computer.maxEnergy()
term=require("term")
running=true
function off()
  running=false
end
require("event").listen("touch",off)

function stt(s)
  s=math.floor(s)
  m=math.floor(s/60)
  s=s-m*60
  h=math.floor(m/60)
  m=m-h*60
  out=""
  if(h>0) then
  out=out..h.." hours "
  end
  if(h>0 or m>0) then
  out=out..m.." mins "
  end
  out=out..s.." seconds"
  return out
end

while(running) do
  energy=computer.energy()
  energydiff=preenergy-energy
  term.clear()
  print("energy: "..math.floor(energy).."/"..maxenergy.."\n")
  print("energy change: "..string.format("%.3f",-energydiff).."\n")
  if(energydiff>0) then
    print("Time remaining: "..stt(energy/energydiff))
  else
    print("Time until charged: "..stt((maxenergy-energy)/-energydiff))
  end
  preenergy=energy
  os.sleep(1)
end