local function esc_label(v)
  v = tostring(v or "")
  v = v:gsub("\\", "\\\\")
  v = v:gsub("\"", "\\\"")
  v = v:gsub("\n", "")
  return v
end

local function load_dhcp_leases()
  local leases = {}
  local fh = io.open("/tmp/dhcp.leases", "r")

  if fh == nil then
    return leases
  end

  for line in fh:lines() do
    local _expires, mac, ip, hostname = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")

    if ip and hostname and hostname ~= "*" then
      leases[ip] = hostname
    end
  end

  fh:close()
  return leases
end

local function load_static_hosts()
  local hosts = {}
  local tmp = {}

  local fh = io.popen("uci show dhcp 2>/dev/null | grep '^dhcp\\.@host'")
  if fh == nil then
    return hosts
  end

  for line in fh:lines() do
    local idx, key, value = line:match("^dhcp%.@host%[(%d+)%]%.([^=]+)='?([^']*)'?")

    if idx and key and value then
      if tmp[idx] == nil then
        tmp[idx] = {}
      end

      tmp[idx][key] = value
    end
  end

  fh:close()

  for _, entry in pairs(tmp) do
    if entry.ip and entry.name then
      hosts[entry.ip] = entry.name
    end
  end

  return hosts
end

local function scrape()
  local leases = load_dhcp_leases()
  local static_hosts = load_static_hosts()

  local rx_metric = metric("nlbwmon_rx_bytes", "gauge")
  local tx_metric = metric("nlbwmon_tx_bytes", "gauge")
  local conns_metric = metric("nlbwmon_connections", "gauge")

  local fh = io.popen("nlbw -c csv 2>/dev/null")
  if fh == nil then
    return
  end

  local first = true

  for line in fh:lines() do
    if first then
      first = false
    else
      line = line:gsub('"', "")

      local family, proto, port, mac, ip, conns, rx_bytes, rx_pkts, tx_bytes, tx_pkts, layer7 =
        line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")

      if ip and rx_bytes and tx_bytes then
        local hostname = static_hosts[ip] or leases[ip] or ip

        local labels = {
          family = esc_label(family),
          proto = esc_label(proto),
          port = esc_label(port),
          mac = esc_label(mac),
          ip = esc_label(ip),
          hostname = esc_label(hostname),
          layer7 = esc_label(layer7 or "unknown")
        }

        rx_metric(labels, tonumber(rx_bytes) or 0)
        tx_metric(labels, tonumber(tx_bytes) or 0)
        conns_metric(labels, tonumber(conns) or 0)
      end
    end
  end

  fh:close()
end

return { scrape = scrape }
