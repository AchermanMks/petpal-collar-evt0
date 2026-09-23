-- Magnitude-based activity estimate; NOT a calibrated pet pedometer/health sensor.
local M={}
local S=_G.STATE.motion
local baseline, high, last_peak = 1,false,-10000
local previous, day, active_ms = nil,nil,0
function M.sample(x,y,z,t)
    local today=_G.PETPAL.clock_valid() and os.date("%Y-%m-%d") or "unsynced"
    if day and today~=day then S.steps=0; active_ms=0; previous=nil end
    day=today; S.day=day
    local dt=previous and math.max(0,math.min(500,t-previous)) or 0; previous=t
    local magnitude=math.sqrt(x*x+y*y+z*z)
    baseline=baseline*.95+magnitude*.05
    local delta=math.abs(magnitude-baseline)
    S.accel_g={x,y,z}; S.ready=true
    if delta>.15 then active_ms=active_ms+dt; S.activity="active"
    else S.activity="resting" end
    if delta>.22 and not high and t-last_peak>=300 then
        S.steps=S.steps+1; last_peak=t; high=true
    elseif delta<.10 then high=false end
    S.active_s=math.floor(active_ms/1000)
    if delta>.15 then S.state="moving"; S.last_motion_tick=t
    elseif t-(S.last_motion_tick or 0)>_G.CFG.gsensor.motion_timeout_s*1000 then S.state="still" end
end
return M
