-- Usage (from the addon folder):  lua5.1 dev/validate.lua .   -- compiles every file the TOC loads
-- compile (not run) every .lua file the TOC loads, including ones pulled in via .xml
local root = arg[1]
local ROOT_FOR_TOC = root
local TOC_NAME = (function()   -- the addon folder holds exactly one .toc
	local p = io.popen('ls "' .. ROOT_FOR_TOC .. '"/*.toc 2>/dev/null')
	local line = p and p:read("*l"); if p then p:close() end
	return assert(line and line:match("([^/]+)%.toc$"), "no .toc found in " .. ROOT_FOR_TOC)
end)()
local function norm(p) return (p:gsub("\\", "/")) end
local files, bad = {}, 0
local function addXml(xml)
  local f = io.open(root .. "/" .. xml); if not f then print("MISSING xml " .. xml); bad = bad + 1; return end
  local dir = xml:match("^(.*)/[^/]*$") or ""
  local body = f:read("*a"):gsub("<!%-%-.-%-%->", "")
  for inc in body:gmatch('<[SI][cn][rc][il][pu][td]e?%s+file="([^"]+)"') do
    local p = (dir ~= "" and dir .. "/" or "") .. norm(inc)
    if p:match("%.xml$") then addXml(p) else files[#files+1] = p end
  end
  f:close()
end
for line in io.lines(root .. "/" .. TOC_NAME .. ".toc") do
  line = line:gsub("\r", "")
  if line ~= "" and not line:match("^#") then
    local p = norm(line)
    if p:match("%.xml$") then addXml(p) else files[#files+1] = p end
  end
end
for _, p in ipairs(files) do
  local fh = io.open(root .. "/" .. p, "rb")
  local src = fh and fh:read("*a"); if fh then fh:close() end
  local fn, err
  if not src then err = "missing file" else src = src:gsub("^\239\187\191", ""); fn, err = loadstring(src, "@" .. p) end
  if not fn then print("FAIL " .. p .. ": " .. tostring(err)); bad = bad + 1 end
end
print(("%d files compiled, %d problems"):format(#files, bad))
