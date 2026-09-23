-- Bounded durable QoS1 queue. Only a broker PUBACK ("sent") removes a record.
-- Individual KV records are recovered by scanning slots, not a fragile head pointer.
local M, records = {}, {}
local limit = math.max(8, math.min(96, (_G.CFG.outbox or {}).max_records or 64))
local ticket = 0
local function key(i) return "pp_q"..i end
for i=1,limit do
    local raw=fskv and fskv.get(key(i))
    if type(raw)=="string" then
        local ok,r=pcall(json.decode,raw)
        if ok and type(r)=="table" and type(r.ticket)=="number" and type(r.payload)=="string" and type(r.topic)=="string" then
            r.slot=i; r.replayed=true; records[i]=r; ticket=math.max(ticket,r.ticket)
        end
    end
end
function M.depth() local n=0; for _ in pairs(records) do n=n+1 end; return n end
function M.oldest()
    local found
    for _,r in pairs(records) do if not found or r.ticket<found.ticket then found=r end end
    return found
end
function M.push(topic,payload,retain)
    if type(payload)~="string" or #payload>3072 then return false,"payload_too_large" end
    local slot
    for i=1,limit do if not records[i] then slot=i; break end end
    -- Never silently evict commands/events. Caller exposes cache_full and retries.
    if not slot then _G.STATE.cache_full=true; return false,"cache_full" end
    ticket=ticket+1
    local r={ticket=ticket,topic=topic,payload=payload,retain=retain==true,slot=slot}
    local encoded=json.encode(r)
    if #encoded>4095 then return false,"payload_too_large" end
    if fskv and not fskv.set(key(slot),encoded) then return false,"storage_failed" end
    records[slot]=r; sys.publish("OUTBOX_READY"); return true
end
function M.confirm(expected)
    local r=records[expected.slot]
    if not r or r.ticket~=expected.ticket then return false end
    if fskv and not fskv.del(key(r.slot)) then return false end
    records[r.slot]=nil; _G.STATE.cache_full=false; return true
end
function M.mark_replayed() for _,r in pairs(records) do r.replayed=true end end
M.persistent=fskv~=nil
M.capacity=limit
return M
