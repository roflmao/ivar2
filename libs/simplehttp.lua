local httpclient = require'handler.http.client'
local uri = require"handler.uri"
local idn = require'idn'
local ev = require'ev'

local uri_parse = uri.parse

local toIDN = function(url)
	local info = uri_parse(url, nil, true)
	info.host = idn.encode(info.host)

	if(info.port) then
		info.host = info.host .. ':' .. info.port
	end

	return string.format(
		'%s://%s%s%s',

		info.scheme,
		info.userinfo or '',
		info.host,
		info.path or ''
	)
end

local function simplehttp(url, callback, stream, limit, visited)
	local sinkSize = 0
	local sink = {}
	local visited = visited or {}
	local method = "GET"
	local data = nil

	local client = httpclient.new(ev.Loop.default)
	if(type(url) == "table") then
		if(url.headers) then
			for k, v in next, url.headers do
				client.headers[k] = v
			end
		end

		if(url.method) then
			method = url.method
		end

		if(url.data) then
			data = url.data
		end

		url = url.url or url[1]
	end

	-- Add support for IDNs.
	url = toIDN(url)

	-- Prevent infinite loops!
	if(visited[url]) then return end
	visited[url] = true

	client:request{
		url = url,
		method = method,
		body = data,
		stream_response = stream,

		on_data = function(request, response, data)
			if(data) then
				sinkSize = sinkSize + #data
				sink[#sink + 1] = data
				if(limit and sinkSize > limit) then
					request.on_finished(request, response)
					-- Cancel it
					request:close()
				end
			end
		end,

		on_finished = function(request, response)
			if(response.status_code == 301 or response.status_code == 302) then
				local location = response.headers.Location
				if(location:sub(1, 4) ~= 'http') then
					local info = uri_parse(url)
					location = string.format('%s://%s%s', info.scheme, info.host, location)
				end

				if(url.headers) then
					location = {
						url = location,
						headers = url.headers
					}
				end

				return simplehttp(location, callback, stream, limit, visited)
			end

			callback(table.concat(sink), url, response)
		end,
	}
end

return simplehttp
