local m = {
  sets = {}
}

local table_size = 9

function m:add_set(set)
  for idx, existing in ipairs(self.sets) do
    local exact_match = false
    local left_t, left_v, right_t, right_v
    for i=1,table_size do
      left_t, left_v = next(set, left_t)
      right_t, right_v = next(existing, right_t)
      exact_match = left_v == right_v
      if not exact_match then
        break
      end
    end
    
    if exact_match then
      table.insert(self.sets, set)
      return {
        first = existing,
        first_idx = idx,
        second = set,
        second_idx = #self.sets
      }
    end
  end
  table.insert(self.sets, set)
end

local function gen_set()
  local tables = {}
  for i=1, table_size do
    tables[{}] = i
  end
  return tables
end

local result

repeat
  result = m:add_set(gen_set())
until result

print("RESULT")
print(result.first_idx, result.second_idx)
print("f,s")
for i=1,table_size do
  local t1, v1 = next(result.first)
  local t2, v2 = next(result.second)
  print(string.format("%s,%s", v1, v2))
  result.first[t1] = nil
  result.second[t2] = nil
end
