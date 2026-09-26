--[[
	ApexGatherer route optimizer.

	Ordering: iterated local search. A nearest-neighbour tour is improved with 2-opt and Or-opt
	moves over each point's closest neighbours; then small random double-bridge kicks shake the
	tour out of its local minimum and the best tour seen is kept. It stops once a run of kicks
	finds nothing shorter.

	Clustered routes are solved as a TSP with neighbourhoods: each route point only has to come
	within the cluster radius of the nodes it stands for, so once the order is fixed every point
	slides toward the straight line between its neighbours as far as that radius allows.

	Edges crossing a taboo area's border cost twice their length plus a zone width, so the
	optimizer goes around taboos whenever that is at all possible. Taboo areas are lists of
	packed coordinates (a closed polygon).
]]
local Apex = ApexGatherer
local Optimizer = {}
Apex.Optimizer = Optimizer

local floor, sqrt, min, max, huge = math.floor, math.sqrt, math.min, math.max, math.huge
local random, atan2 = math.random, math.atan2
local tinsert, sort = table.insert, table.sort
local yield, resume, costatus, cocreate = coroutine.yield, coroutine.resume, coroutine.status, coroutine.create
local debugprofilestop, GetTime, wipe = debugprofilestop, GetTime, wipe

local EPS = 1e-7
local NEIGHBOURS = 10         -- candidate list size per point
local MAX_KICK_SEGMENT = 30   -- longest segment a double-bridge kick moves
local SLICE_MS = 8            -- CPU time a background job may use per frame
local FOREGROUND_MS = 4000    -- a foreground run never freezes the game longer than this

-- route coordinates pack x and y (0..1, 4 decimals) as xxxxyyyy
local function unpackCoord(c)
	return floor(c / 10000) / 10000, (c % 10000) / 10000
end
local function packCoord(x, y)
	return floor(x * 10000 + 0.5) * 10000 + floor(y * 10000 + 0.5)
end


-- Background jobs: a coroutine resumed once per frame, handing control back when its slice is used

local sliceEnd = 0
local function breathe()
	if debugprofilestop() > sliceEnd then
		yield()
	end
end

local function newJob(errorText)
	local job = CreateFrame("Frame")
	job.running = false
	job.errorText = errorText
	return job
end
local solver = newJob("route optimizing failed:")

local function stopJob(job)
	job:SetScript("OnUpdate", nil)
	job.running, job.co, job.nodes, job.finishFunc, job.statusFunc = false, nil, nil, nil, nil
end

local function stepJob(job)
	sliceEnd = debugprofilestop() + SLICE_MS
	local ok, a, b, c, d, e = resume(job.co)
	if not ok then
		stopJob(job)
		Apex:Print(job.errorText)
		Apex:Print(a)
	elseif costatus(job.co) == "dead" then
		local finish = job.finishFunc
		stopJob(job)
		if finish then finish(a, b, c, d, e) end
	end
end

-- returns 1 when started, 2 when the job is already busy, 3 plus the error when it failed to start
local function startJob(job, func, ...)
	if job.running then return 2 end
	job.co = cocreate(func)
	sliceEnd = debugprofilestop() + SLICE_MS
	local ok, err = resume(job.co, ...)
	if not ok then
		job.co = nil
		return 3, err
	end
	job.running = true
	job:SetScript("OnUpdate", stepJob)
	return 1
end


-- Taboo borders

local function tabooBorders(taboos)
	local segs, count = {}, 0
	for t = 1, #taboos do
		local pts = taboos[t]
		local num = pts and #pts or 0
		if num >= 2 then
			local px, py = unpackCoord(pts[num])
			for k = 1, num do
				local x, y = unpackCoord(pts[k])
				count = count + 1
				segs[count] = { px, py, x, y, min(px, x), max(px, x), min(py, y), max(py, y) }
				px, py = x, y
			end
		end
	end
	return count > 0 and segs or nil
end

-- does the segment (x1,y1)-(x2,y2) touch or cross any border segment?
local function crossesBorder(segs, x1, y1, x2, y2)
	local lox, hix = min(x1, x2), max(x1, x2)
	local loy, hiy = min(y1, y2), max(y1, y2)
	local dx, dy = x2 - x1, y2 - y1
	for k = 1, #segs do
		local s = segs[k]
		if s[6] >= lox and s[5] <= hix and s[8] >= loy and s[7] <= hiy then
			local sx, sy, ex, ey = s[1], s[2], s[3], s[4]
			local d1 = dx * (sy - y1) - dy * (sx - x1)
			local d2 = dx * (ey - y1) - dy * (ex - x1)
			if not ((d1 > 0 and d2 > 0) or (d1 < 0 and d2 < 0)) then
				local fx, fy = ex - sx, ey - sy
				local d3 = fx * (y1 - sy) - fy * (x1 - sx)
				local d4 = fx * (y2 - sy) - fy * (x2 - sx)
				if not ((d3 > 0 and d4 > 0) or (d3 < 0 and d4 < 0)) then
					return true
				end
			end
		end
	end
	return false
end


-- Ordering

-- Finds a short round trip through n points. D is the flat n*n distance matrix
-- (D[(a-1)*n + b]); returns the best tour found (array of point indices) and the kick count.
local function solveOrder(n, D, thorough, bg, report)
	local K = min(NEIGHBOURS, n - 1)
	local startMS = debugprofilestop()

	-- the K closest points to each point, nearest first
	local near = {}
	for a = 1, n do
		local rowA, list, dist, cnt = (a - 1) * n, {}, {}, 0
		for b = 1, n do
			if b ~= a then
				local d = D[rowA + b]
				if cnt < K or d < dist[cnt] then
					if cnt < K then cnt = cnt + 1 end
					local k = cnt
					while k > 1 and dist[k - 1] > d do
						list[k], dist[k] = list[k - 1], dist[k - 1]
						k = k - 1
					end
					list[k], dist[k] = b, d
				end
			end
		end
		near[a] = list
		if bg then breathe() end
	end

	-- start from the nearest-neighbour tour or the current order, whichever is shorter
	local tour, pos, used = {}, {}, {}
	local cur = 1
	tour[1], used[1] = 1, true
	for i = 2, n do
		local nextCity
		local list = near[cur]
		for k = 1, K do
			if not used[list[k]] then nextCity = list[k]; break end
		end
		if not nextCity then
			local rowC, bestD = (cur - 1) * n, huge
			for c = 1, n do
				if not used[c] and D[rowC + c] < bestD then nextCity, bestD = c, D[rowC + c] end
			end
		end
		tour[i], used[nextCity] = nextCity, true
		cur = nextCity
	end
	local nnLen, idLen = D[(tour[n] - 1) * n + tour[1]], D[(n - 1) * n + 1]
	for i = 2, n do
		nnLen = nnLen + D[(tour[i - 1] - 1) * n + tour[i]]
		idLen = idLen + D[(i - 2) * n + i]
	end
	if idLen <= nnLen then
		for i = 1, n do tour[i] = i end
	end
	for i = 1, n do pos[tour[i]] = i end

	local function tourLength()
		local len, prev = 0, tour[n]
		for i = 1, n do
			local c = tour[i]
			len = len + D[(prev - 1) * n + c]
			prev = c
		end
		return len
	end

	-- cities whose surroundings changed and need another look
	local stack, queued, top = {}, {}, 0
	local function push(c)
		if not queued[c] then
			top = top + 1
			stack[top] = c
			queued[c] = true
		end
	end

	-- reverse tour positions i..j (walking forward, wrapping); flips the shorter side
	local function reverse(i, j)
		local len = j - i
		if len < 0 then len = len + n end
		len = len + 1
		if len * 2 > n then
			i, j = j + 1, i - 1
			if i > n then i = 1 end
			if j < 1 then j = n end
			len = n - len
		end
		for _ = 1, floor(len / 2) do
			local a, b = tour[i], tour[j]
			tour[i], pos[b] = b, i
			tour[j], pos[a] = a, j
			i = i + 1
			if i > n then i = 1 end
			j = j - 1
			if j < 1 then j = n end
		end
	end

	-- 2-opt: replace two edges with two shorter ones, one of them to a close neighbour of a
	local function twoOpt(a)
		local rowA, list, pa = (a - 1) * n, near[a], pos[a]
		local b = tour[pa == n and 1 or pa + 1]
		local dab = D[rowA + b]
		for k = 1, K do
			local c = list[k]
			local dac = D[rowA + c]
			if dac >= dab then break end
			local pc = pos[c]
			local d = tour[pc == n and 1 or pc + 1]
			if d ~= a then
				local gain = dab + D[(c - 1) * n + d] - dac - D[(b - 1) * n + d]
				if gain > EPS then
					reverse(pos[b], pc)
					push(a); push(b); push(c); push(d)
					return gain
				end
			end
		end
		b = tour[pa == 1 and n or pa - 1]
		dab = D[rowA + b]
		for k = 1, K do
			local c = list[k]
			local dac = D[rowA + c]
			if dac >= dab then break end
			local pc = pos[c]
			local d = tour[pc == 1 and n or pc - 1]
			if d ~= a then
				local gain = dab + D[(c - 1) * n + d] - dac - D[(b - 1) * n + d]
				if gain > EPS then
					reverse(pa, pos[d])
					push(a); push(b); push(c); push(d)
					return gain
				end
			end
		end
		return 0
	end

	-- move tour positions i..i+len-1 so they follow city x (reversed if asked)
	local seg, tmp = {}, {}
	local function moveSegment(i, len, x, reversed)
		for k = 1, len do
			local p = i + k - 1
			if p > n then p = p - n end
			seg[k] = tour[p]
		end
		local p, m = i + len, 0
		if p > n then p = p - n end
		for _ = 1, n - len do
			local c = tour[p]
			m = m + 1
			tmp[m] = c
			if c == x then
				if reversed then
					for k = len, 1, -1 do m = m + 1; tmp[m] = seg[k] end
				else
					for k = 1, len do m = m + 1; tmp[m] = seg[k] end
				end
			end
			p = p + 1
			if p > n then p = 1 end
		end
		for k = 1, n do
			local c = tmp[k]
			tour[k], pos[c] = c, k
		end
	end

	-- Or-opt: take a run of 1-3 cities starting or ending at a and slot it in next to a close
	-- neighbour of either end, in whichever direction is shorter
	local maxRun = min(3, n - 3)
	local function orOpt(a)
		local pa = pos[a]
		for len = 1, maxRun do
			for side = 1, len == 1 and 1 or 2 do
				local i = side == 1 and pa or pa - len + 1
				if i < 1 then i = i + n end
				local j = i + len - 1
				if j > n then j = j - n end
				local s1, s2 = tour[i], tour[j]
				local p = tour[i == 1 and n or i - 1]
				local q = tour[j == n and 1 or j + 1]
				local removeGain = D[(p - 1) * n + s1] + D[(s2 - 1) * n + q] - D[(p - 1) * n + q]
				if removeGain > EPS then
					for e = 1, 2 do
						local s = e == 1 and s1 or s2
						local list, rowS = near[s], (s - 1) * n
						for k = 1, K do
							local c = list[k]
							if D[rowS + c] >= removeGain then break end
							local pc = pos[c]
							local off = pc - i
							if off < 0 then off = off + n end
							if off >= len then
								for place = 1, 2 do
									local x, y
									if place == 1 then
										if c ~= p then x, y = c, tour[pc == n and 1 or pc + 1] end
									elseif c ~= q then
										x, y = tour[pc == 1 and n or pc - 1], c
									end
									if x then
										local rowX, dxy = (x - 1) * n, D[(x - 1) * n + y]
										local fwd = D[rowX + s1] + D[(s2 - 1) * n + y] - dxy
										local rev = D[rowX + s2] + D[(s1 - 1) * n + y] - dxy
										local add, reversed = fwd, false
										if rev < fwd then add, reversed = rev, true end
										local gain = removeGain - add
										if gain > EPS then
											moveSegment(i, len, x, reversed)
											push(p); push(q); push(s1); push(s2); push(x); push(y)
											return gain
										end
									end
								end
							end
						end
					end
				end
			end
		end
		return 0
	end

	local function localSearch()
		local gained, steps = 0, 0
		while top > 0 do
			local a = stack[top]
			top = top - 1
			queued[a] = nil
			local g = twoOpt(a)
			if g == 0 then g = orOpt(a) end
			gained = gained + g
			steps = steps + 1
			if bg and steps % 64 == 0 then breathe() end
		end
		return gained
	end

	-- double bridge on two short neighbouring runs: ...a [B] [C] d... becomes ...a [C] [B] d...
	local maxSeg = max(1, min(MAX_KICK_SEGMENT, floor((n - 1) / 2)))
	local function kick()
		local len1, len2 = random(1, maxSeg), random(1, maxSeg)
		local i = random(1, n)
		local pa = i == 1 and n or i - 1
		local pb2 = (i + len1 - 2) % n + 1
		local pc1 = (i + len1 - 1) % n + 1
		local pc2 = (i + len1 + len2 - 2) % n + 1
		local pd = (i + len1 + len2 - 1) % n + 1
		local a, b1, b2, c1, c2, d = tour[pa], tour[i], tour[pb2], tour[pc1], tour[pc2], tour[pd]
		local delta = D[(a - 1) * n + c1] + D[(c2 - 1) * n + b1] + D[(b2 - 1) * n + d]
			- D[(a - 1) * n + b1] - D[(b2 - 1) * n + c1] - D[(c2 - 1) * n + d]
		for k = 1, len1 + len2 do tmp[k] = tour[(i + k - 2) % n + 1] end
		local p = i
		for k = len1 + 1, len1 + len2 do
			local c = tmp[k]
			tour[p], pos[c] = c, p
			p = p % n + 1
		end
		for k = 1, len1 do
			local c = tmp[k]
			tour[p], pos[c] = c, p
			p = p % n + 1
		end
		push(a); push(b1); push(b2); push(c1); push(c2); push(d)
		return delta
	end

	for c = n, 1, -1 do push(c) end
	localSearch()
	local curLen = tourLength()
	local best, bestLen = {}, curLen
	for k = 1, n do best[k] = tour[k] end

	-- a small route has few distinct tours, so it settles quickly; a big one gets more tries
	local patience = max(150, 3 * n) * (thorough and 3 or 1)
	local idle, kicks = 0, 0
	while idle < patience and n >= 5 do
		kicks = kicks + 1
		curLen = curLen + kick()
		curLen = curLen - localSearch()
		if curLen < bestLen - EPS then
			curLen = tourLength()
			bestLen = curLen
			for k = 1, n do best[k] = tour[k] end
			idle = 0
		else
			idle = idle + 1
			if curLen > bestLen + EPS then
				for k = 1, n do
					local c = best[k]
					tour[k], pos[c] = c, k
				end
				curLen = bestLen
			end
		end
		if bg then
			if debugprofilestop() > sliceEnd then
				if report then report(kicks, idle / patience, bestLen) end
				yield()
			end
		elseif debugprofilestop() - startMS > FOREGROUND_MS then
			break
		end
	end
	return best, kicks
end


-- Neighbourhoods: slide each clustered point toward its neighbours' straight line

-- Moves each point of an ordered route toward the line between its neighbours, as far as it can
-- go while every node it stands for stays within radius. Returns the new coordinates.
local function pullPoints(coords, members, radius, zoneW, zoneH, borders, bg)
	local n = #coords
	local xs, ys = {}, {}
	for i = 1, n do xs[i], ys[i] = unpackCoord(coords[i]) end
	local mx, my = {}, {}
	for i = 1, n do
		local list, lx, ly = members[i], {}, {}
		for k = 1, #list do lx[k], ly[k] = unpackCoord(list[k]) end
		mx[i], my[i] = lx, ly
	end
	-- yards are the metric, so the radius check works in scaled coordinates
	local r2 = radius * radius
	local function fits(i, x, y)
		local lx, ly = mx[i], my[i]
		for k = 1, #lx do
			local dx, dy = (x - lx[k]) * zoneW, (y - ly[k]) * zoneH
			if dx * dx + dy * dy > r2 then return false end
		end
		return true
	end
	local function crossesAt(i, x, y, px, py, nx, ny)
		return borders and (crossesBorder(borders, px, py, x, y) or crossesBorder(borders, x, y, nx, ny))
	end

	for _ = 1, 8 do
		local moved = false
		for i = 1, n do
			local px, py = xs[i == 1 and n or i - 1], ys[i == 1 and n or i - 1]
			local nx, ny = xs[i == n and 1 or i + 1], ys[i == n and 1 or i + 1]
			local x, y = xs[i], ys[i]
			-- the closest point to (x, y) on the neighbours' line, in yards
			local ax, ay = (nx - px) * zoneW, (ny - py) * zoneH
			local len2 = ax * ax + ay * ay
			local t = 0
			if len2 > 0 then
				t = (((x - px) * zoneW) * ax + ((y - py) * zoneH) * ay) / len2
				if t < 0 then t = 0 elseif t > 1 then t = 1 end
			end
			local tx, ty = px + (nx - px) * t, py + (ny - py) * t
			local wasCrossing = crossesAt(i, x, y, px, py, nx, ny)
			-- slide from the current point toward the target: find how far it can go
			local lo, hi = 0, 1
			local cx, cy = unpackCoord(packCoord(tx, ty))
			if fits(i, cx, cy) and (wasCrossing or not crossesAt(i, cx, cy, px, py, nx, ny)) then
				lo = 1
			else
				for _ = 1, 12 do
					local mid = (lo + hi) / 2
					local sx, sy = unpackCoord(packCoord(x + (tx - x) * mid, y + (ty - y) * mid))
					if fits(i, sx, sy) and (wasCrossing or not crossesAt(i, sx, sy, px, py, nx, ny)) then lo = mid else hi = mid end
				end
			end
			if lo > 0 then
				local c = packCoord(x + (tx - x) * lo, y + (ty - y) * lo)
				local sx, sy = unpackCoord(c)
				if (sx ~= x or sy ~= y) and fits(i, sx, sy) then
					xs[i], ys[i] = sx, sy
					moved = true
				end
			end
		end
		if bg then breathe() end
		if not moved then break end
	end
	local out = {}
	for i = 1, n do out[i] = packCoord(xs[i], ys[i]) end
	return out
end


-- Public API

function Optimizer:IsRunning()
	return solver.running, solver.nodes
end

function Optimizer:SetFinishFunction(func)
	assert(type(func) == "function", "SetFinishFunction() expected function in 1st argument, got "..type(func).." instead.")
	solver.finishFunc = func
end

function Optimizer:SetStatusFunction(func)
	assert(type(func) == "function", "SetStatusFunction() expected function in 1st argument, got "..type(func).." instead.")
	solver.statusFunc = func
end

function Optimizer:SolveInBackground(nodes, metadata, taboos, zoneID, parameters, path, radius)
	local state, err = startJob(solver, Optimizer.Solve, Optimizer, nodes, metadata, taboos, zoneID, parameters, path, true, radius)
	if state == 1 then solver.nodes = nodes end
	return state, err
end

-- Optimizes the order of a route. Returns the new route, its metadata (clustered routes), the
-- length in yards, the number of kicks tried and the time taken in seconds. radius is the
-- cluster radius of a clustered route; its points then also move toward straighter lines.
function Optimizer:Solve(nodes, metadata, taboos, zoneID, parameters, path, nonblocking, radius)
	assert(type(nodes) == "table", "Solve() expected table in 1st argument, got "..type(nodes).." instead.")
	assert(type(taboos) == "table", "Solve() expected table in 3rd argument, got "..type(taboos).." instead.")
	assert(type(parameters) == "table", "Solve() expected table in 5th argument, got "..type(parameters).." instead.")
	if type(path) == "table" then wipe(path) else path = {} end
	local bg = nonblocking and true or false
	-- the caller attaches its status and finish callbacks after starting a background run
	if bg then yield() end
	local started = bg and GetTime() or debugprofilestop()

	local n = #nodes
	local meta
	if metadata then
		meta = {}
		for i = 1, n do
			local src, copy = metadata[i], {}
			for k = 1, #src do copy[k] = src[k] end
			meta[i] = copy
		end
	end
	if n < 4 then
		for i = 1, n do path[i] = nodes[i] end
		return path, meta, Optimizer:PathLength(path, zoneID), 0, 0
	end

	local zoneW, zoneH = Apex.HBD:GetZoneSize(zoneID)
	local borders = tabooBorders(taboos)
	local xs, ys = {}, {}
	for i = 1, n do xs[i], ys[i] = unpackCoord(nodes[i]) end
	local D = {}
	for k = 1, n * n do D[k] = 0 end
	for a = 1, n do
		local xa, ya, rowA = xs[a], ys[a], (a - 1) * n
		for b = a + 1, n do
			local dx, dy = (xs[b] - xa) * zoneW, (ys[b] - ya) * zoneH
			local d = sqrt(dx * dx + dy * dy)
			if borders and crossesBorder(borders, xa, ya, xs[b], ys[b]) then d = d * 2 + zoneW end
			D[rowA + b] = d
			D[(b - 1) * n + a] = d
		end
		if bg then breathe() end
	end

	local report = bg and function(kicks, progress, length)
		if solver.statusFunc then solver.statusFunc(kicks, progress, length) end
	end
	local order, kicks = solveOrder(n, D, parameters.thorough, bg, report)

	-- keep the route's first point first, so re-optimizing doesn't spin the route around
	local first = 1
	for i = 1, n do
		if order[i] == 1 then first = i; break end
	end
	local newMeta = meta and {}
	for i = 1, n do
		local c = order[(first + i - 2) % n + 1]
		path[i] = nodes[c]
		if meta then newMeta[i] = meta[c] end
	end

	if newMeta and radius and radius > 0 then
		local pulled = pullPoints(path, newMeta, radius, zoneW, zoneH, borders, bg)
		for i = 1, n do path[i] = pulled[i] end
	end

	local elapsed
	if bg then
		elapsed = GetTime() - started
	else
		elapsed = (debugprofilestop() - started) / 1000
	end
	return path, newMeta, Optimizer:PathLength(path, zoneID), kicks, elapsed
end

-- Joins coord to the cluster at index i if the cluster point, moved to the member-weighted
-- average, stays within radius of every member (the new one included).
local function joinCluster(nodes, metadata, i, coord, radius, zoneW, zoneH)
	local list = metadata[i]
	local num = #list
	local x, y = unpackCoord(coord)
	local cx, cy = unpackCoord(nodes[i])
	local c = packCoord((cx * num + x) / (num + 1), (cy * num + y) / (num + 1))
	cx, cy = unpackCoord(c)
	for k = 0, num do
		local mx, my = unpackCoord(k == 0 and coord or list[k])
		local dx, dy = (cx - mx) * zoneW, (cy - my) * zoneH
		if sqrt(dx * dx + dy * dy) > radius then return false end
	end
	list[num + 1] = coord
	nodes[i] = c
	return true
end

-- Adds a node where it lengthens the route least; on a clustered route it joins the nearer
-- neighbouring cluster when that cluster can take it. Returns the new length.
function Optimizer:InsertPoint(nodes, metadata, zoneID, nodeID, radius)
	assert(type(nodes) == "table", "InsertPoint() expected table in 1st argument, got "..type(nodes).." instead.")
	local n = #nodes
	if n < 3 then
		nodes[n + 1] = nodeID
		if metadata then metadata[n + 1] = { nodeID } end
		return Optimizer:PathLength(nodes, zoneID)
	end

	local zoneW, zoneH = Apex.HBD:GetZoneSize(zoneID)
	local xs, ys = {}, {}
	for i = 1, n do xs[i], ys[i] = unpackCoord(nodes[i]) end
	local x, y = unpackCoord(nodeID)
	local function toNew(i)
		local dx, dy = (xs[i] - x) * zoneW, (ys[i] - y) * zoneH
		return sqrt(dx * dx + dy * dy)
	end

	local bestCost, bestI = huge, n
	for i = 1, n do
		local j = i == n and 1 or i + 1
		local dx, dy = (xs[j] - xs[i]) * zoneW, (ys[j] - ys[i]) * zoneH
		local cost = toNew(i) + toNew(j) - sqrt(dx * dx + dy * dy)
		if cost < bestCost then bestCost, bestI = cost, i end
	end
	local nextI = bestI == n and 1 or bestI + 1

	if metadata then
		local near, far = bestI, nextI
		if toNew(bestI) > toNew(nextI) then near, far = nextI, bestI end
		if joinCluster(nodes, metadata, near, nodeID, radius, zoneW, zoneH)
		or joinCluster(nodes, metadata, far, nodeID, radius, zoneW, zoneH) then
			return Optimizer:PathLength(nodes, zoneID)
		end
	end
	tinsert(nodes, bestI + 1, nodeID)
	if metadata then tinsert(metadata, bestI + 1, { nodeID }) end
	return Optimizer:PathLength(nodes, zoneID)
end

function Optimizer:PathLength(nodes, zoneID)
	assert(type(nodes) == "table", "PathLength() expected table in 1st argument, got "..type(nodes).." instead.")
	local n = #nodes
	if n <= 1 then return 0 end
	local zoneW, zoneH = Apex.HBD:GetZoneSize(zoneID)
	local length = 0
	local px, py = unpackCoord(nodes[n])
	for i = 1, n do
		local x, y = unpackCoord(nodes[i])
		local dx, dy = (x - px) * zoneW, (y - py) * zoneH
		length = length + sqrt(dx * dx + dy * dy)
		px, py = x, y
	end
	return length
end

-- Merges nearby nodes into cluster points, closest pair first. Two points merge when the
-- member-weighted average of the pair stays within radius of every member of both. Keeps the
-- route order; returns the cluster points, their member lists and the route length.
function Optimizer:Cluster(nodes, zoneID, radius, nonblocking)
	local bg = nonblocking and true or false
	if bg then yield() end
	local n = #nodes
	local zoneW, zoneH = Apex.HBD:GetZoneSize(zoneID)
	local diameter = radius * 2

	local coord, members, alive, xs, ys = {}, {}, {}, {}, {}
	for i = 1, n do
		local c = nodes[i]
		coord[i], members[i], alive[i] = c, { c }, true
		xs[i], ys[i] = unpackCoord(c)
	end
	local function dist(i, j)
		local dx, dy = (xs[j] - xs[i]) * zoneW, (ys[j] - ys[i]) * zoneH
		return sqrt(dx * dx + dy * dy)
	end

	-- pairs (i < j, keyed i*W + j) that failed to merge; cleared when either side changes
	local W = n + 1
	local blocked = {}
	-- for each point i, its closest mergeable partner j > i (lowest j on ties)
	local partner, partnerD = {}, {}
	local function findPartner(i)
		local best, bestD = nil, huge
		for j = i + 1, n do
			if alive[j] and not blocked[i * W + j] then
				local d = dist(i, j)
				if d <= diameter and d < bestD then best, bestD = j, d end
			end
		end
		partner[i], partnerD[i] = best, bestD
	end
	for i = 1, n do
		findPartner(i)
		if bg and i % 32 == 0 then breathe() end
	end

	while true do
		local a, bestD = nil, huge
		for i = 1, n do
			if alive[i] and partner[i] and partnerD[i] < bestD then a, bestD = i, partnerD[i] end
		end
		if not a then break end
		local b = partner[a]

		local ma, mb = members[a], members[b]
		local na, nb = #ma, #mb
		local c = packCoord((xs[a] * na + xs[b] * nb) / (na + nb), (ys[a] * na + ys[b] * nb) / (na + nb))
		local x, y = unpackCoord(c)
		local fits = true
		for k = 1, na + nb do
			local px, py = unpackCoord(k <= na and ma[k] or mb[k - na])
			local dx, dy = (x - px) * zoneW, (y - py) * zoneH
			if sqrt(dx * dx + dy * dy) > radius then fits = false; break end
		end

		if fits then
			for k = 1, nb do ma[na + k] = mb[k] end
			coord[a], xs[a], ys[a] = c, x, y
			alive[b], members[b] = false, nil
			for j = 1, n do
				if alive[j] and j ~= a then blocked[j < a and j * W + a or a * W + j] = nil end
			end
			findPartner(a)
			for k = 1, a - 1 do
				if alive[k] then
					if partner[k] == a or partner[k] == b then
						findPartner(k)
					else
						local d = dist(k, a)
						if d <= diameter and (d < partnerD[k] or (d == partnerD[k] and a < partner[k])) then
							partner[k], partnerD[k] = a, d
						end
					end
				end
			end
			for k = a + 1, b - 1 do
				if alive[k] and partner[k] == b then findPartner(k) end
			end
		else
			blocked[a * W + b] = true
			findPartner(a)
		end
		if bg then breathe() end
	end

	local outNodes, outMeta = {}, {}
	for i = 1, n do
		if alive[i] then
			outNodes[#outNodes + 1] = coord[i]
			outMeta[#outMeta + 1] = members[i]
		end
	end
	return outNodes, outMeta, Optimizer:PathLength(outNodes, zoneID)
end

