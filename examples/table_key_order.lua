local tables = {}
for i=1, 10 do
  tables[{}] = i
end

for i=1, 10 do
  local t, v = next(tables)
  local tp = tonumber(tostring(t):match("table: 0x(.+)"), 16)
  print(tp, v)
  tables[t] = nil
end
