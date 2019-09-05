dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local ids = {}
local original_fails = 0

function get(data,name)
    return data:match("<"..name..">(.-)</"..name..">")
end

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "facebook%.com")
      or string.match(url, "^https?://[^/]*youtube%.com")then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  for s in string.gmatch(url, "([0-9a-f]+)") do
    if ids[s] then
      return true
    end
  end

  if parenturl ~= nil
      and string.match(parenturl, "^https?://theartistunion%.com/api/v3/tracks/[0-9a-f]+%.json$") then
    return true
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}]") then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
      and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  if string.match(url, "^https?://theartistunion%.com/api/v3/tracks/[0-9a-f]+%.json$") then
    ids[string.match(url, "([0-9a-f]+)%.json$")] = true
    original_fails = 0
  end

  if status_code ~= 200 and string.match(url, "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.[a-z0-9]+$") then
    original_fails = original_fails + 1
    if original_fails == 1 then
      io.stdout:write("Could not get original file...\n")
    end
  end

  if string.match(url, "^https?://[^%.]+%.cloudfront%.net")
    and status_code == 404 then
  io.stdout:write("Hit 404 on cloudfront CDN\n")
  io.stdout:write("Testing url " .. url .. "\n")
  f=io.popen("curl -s " .. url); testurl=f:read"*a"; f:close()
  keystate = get(testurl,"Code")
    if string.match(keystate, "NoSuchKey") then
      io.stdout:write("Track source files have been removed...\n")
    elseif not string.match(keystate, "NoSuchKey") then
      io.stdout:write("Some error has happened")
      abortgrab = true
    end
  end

  if allowed(url, nil)
      and not string.match(url, "^https?://[^%.]+%.cloudfront%.net")
      and status_code ~= 404 then
    html = read_file(file)
    if string.match(url, "^https?://theartistunion%.com/api/v3/tracks/[0-9a-f]+%.json$") then
      identifier = string.match(url, "^https?://theartistunion%.com/api/v3/tracks/([0-9a-f]+)%.json$")
      check("https://theartistunion.com/api/v3/tracks/" .. identifier .. "/related.json")
      check("https://theartistunion.com/tracks/" .. identifier)
      json = load_json_file(html)
      if json["audio_source"] == '' then
        io.stdout:write("Missing audio_source URL...\n")
      end
	  if abortgrab == false then
        if not (string.match(json["audio_source"], "^https?://[^%.]+%.cloudfront%.net/tracks/stream_files/.+%.mp3[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.wav[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.mp3[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.mp4[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.m4a[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.flac[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+%.bin[%?0-9]+$")
            or string.match(json["audio_source"],  "^https?://[^%.]+%.cloudfront%.net/tracks/original_files/.+[%?0-9]+$")
            or string.match(json["audio_source"],  "https?://content%.theartistunion%.com/tracks/audio/%x+/.+%.mp3$")
            or string.match(json["audio_source"], "^https?://content%.theartistunion%.com/tracks/audio/stream_encode/.+%.mp3$")) then
          io.stdout:write("Strange looking audio_source URL...\n")
          abortgrab = true
        end
        if abortgrab == false and string.match(json["audio_source"], "%'") then
          audio_source = json["audio_source"]
          audio_source = audio_source:gsub("%'","%%27")
          check(audio_source)
        end
        if abortgrab == false and string.match(json["audio_source"], "%,") then
          audio_source = json["audio_source"]
          audio_source = audio_source:gsub("%,","%%2C")
          check(audio_source)
        end
        if abortgrab == false then
          check(json["audio_source"])
        end
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 300 and status_code <= 399) then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true then
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 403 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 8
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
