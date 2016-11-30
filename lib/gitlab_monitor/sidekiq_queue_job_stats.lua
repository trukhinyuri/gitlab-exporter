--
-- Adapted from https://github.com/mperham/sidekiq/blob/2f9258e4fe77991c526f7a65c92bcf792eef8338/lib/sidekiq/api.rb#L231
--
local queue_name      = KEYS[1]
local initial_size    = redis.call('llen', queue_name)
local deleted_size    = 0
local page            = 0
local page_size       = 2000
local temp_job_stats  = {}
local final_job_stats = {}

while true do
  local range_start = page * page_size - deleted_size
  local range_end   = range_start + page_size - 1
  local entries     = redis.call('lrange', queue_name, range_start, range_end)

  if #entries == 0 then
    break
  end

  page = page + 1

  for index, entry in next, entries do
    local class = cjson.decode(entry)['class']
    if class ~= nil then
      if temp_job_stats[class] ~= nil then
        temp_job_stats[class] = temp_job_stats[class] + 1
      else
        temp_job_stats[class] = 1
      end
    end
  end

  deleted_size = initial_size - redis.call('llen', queue_name)
end

for class, count in next, temp_job_stats do
  local stat_entry = {class, count}
  table.insert(final_job_stats, stat_entry)
end

return final_job_stats
