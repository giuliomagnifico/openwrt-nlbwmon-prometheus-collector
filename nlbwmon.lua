local function esc_label(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\")
  value = value:gsub("\"", "\\\"")
  value = value:gsub("\r", "")
  value = value:gsub("\n", "")
  return value
end

local function normalize_mac(mac)
  return tostring(mac or ""):lower()
end

local function unquote(value)
  value = tostring(value or "")

  if value:sub(1, 1) == '"' and value:sub(-1) == '"' then
    value = value:sub(2, -2)
  end

  return value
end

local function split_tsv(line)
  local fields = {}

  for field in (line .. "\t"):gmatch("(.-)\t") do
    fields[#fields + 1] = unquote(field)
  end

  return fields
end

local function build_header_map(line)
  local header = {}

  for index, name in ipairs(split_tsv(line)) do
    header[name] = index
  end

  return header
end

local function load_dhcp_leases()
  local by_ip = {}
  local by_mac = {}

  local fh = io.open("/tmp/dhcp.leases", "r")
  if fh == nil then
    return by_ip, by_mac
  end

  for line in fh:lines() do
    local _expires, mac, ip, hostname =
      line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")

    if hostname and hostname ~= "*" then
      if ip then
        by_ip[ip] = hostname
      end

      if mac then
        by_mac[normalize_mac(mac)] = hostname
      end
    end
  end

  fh:close()

  return by_ip, by_mac
end

local function load_static_hosts()
  local entries = {}
  local by_ip = {}
  local by_mac = {}

  local fh = io.popen("uci -q show dhcp 2>/dev/null")
  if fh == nil then
    return by_ip, by_mac
  end

  for line in fh:lines() do
    local index, key, value =
      line:match("^dhcp%.@host%[(%d+)%]%.([^=]+)='(.*)'$")

    if index and key and value then
      entries[index] = entries[index] or {}
      entries[index][key] = value
    end
  end

  fh:close()

  for _, entry in pairs(entries) do
    if entry.name then
      if entry.ip then
        by_ip[entry.ip] = entry.name
      end

      if entry.mac then
        by_mac[normalize_mac(entry.mac)] = entry.name
      end
    end
  end

  return by_ip, by_mac
end

local function resolve_hostname(ip, mac, static_ip, static_mac, lease_ip, lease_mac)
  local normalized_mac = normalize_mac(mac)

  return static_ip[ip]
    or static_mac[normalized_mac]
    or lease_ip[ip]
    or lease_mac[normalized_mac]
    or ip
    or "unknown"
end

local function make_series_key(labels)
  return table.concat({
    labels.family,
    labels.proto,
    labels.port,
    labels.mac,
    labels.ip,
    labels.hostname,
    labels.layer7
  }, "\0")
end

local function scrape()
  local lease_ip, lease_mac = load_dhcp_leases()
  local static_ip, static_mac = load_static_hosts()

  local rx_metric = metric("nlbwmon_rx_bytes", "counter")
  local tx_metric = metric("nlbwmon_tx_bytes", "counter")
  local conns_metric = metric("nlbwmon_connections", "counter")

  local fh = io.popen("nlbw -c csv 2>/dev/null")
  if fh == nil then
    return
  end

  local header_line = fh:read("*l")
  if header_line == nil then
    fh:close()
    return
  end

  local header = build_header_map(header_line)
  local required = {
    "family",
    "proto",
    "port",
    "mac",
    "ip",
    "conns",
    "rx_bytes",
    "tx_bytes"
  }

  for _, column in ipairs(required) do
    if header[column] == nil then
      fh:close()
      return
    end
  end

  local series = {}

  for line in fh:lines() do
    local fields = split_tsv(line)

    local family = fields[header.family]
    local proto = fields[header.proto]
    local port = fields[header.port]
    local mac = fields[header.mac]
    local ip = fields[header.ip]
    local conns = tonumber(fields[header.conns])
    local rx_bytes = tonumber(fields[header.rx_bytes])
    local tx_bytes = tonumber(fields[header.tx_bytes])

    local layer7 = "unknown"
    if header.layer7 and fields[header.layer7] and fields[header.layer7] ~= "" then
      layer7 = fields[header.layer7]
    end

    if ip and ip ~= "" and rx_bytes and tx_bytes and conns then
      local hostname = resolve_hostname(
        ip,
        mac,
        static_ip,
        static_mac,
        lease_ip,
        lease_mac
      )

      local labels = {
        family = esc_label(family),
        proto = esc_label(proto),
        port = esc_label(port),
        mac = esc_label(normalize_mac(mac)),
        ip = esc_label(ip),
        hostname = esc_label(hostname),
        layer7 = esc_label(layer7)
      }

      local key = make_series_key(labels)

      if series[key] == nil then
        series[key] = {
          labels = labels,
          rx_bytes = 0,
          tx_bytes = 0,
          connections = 0
        }
      end

      series[key].rx_bytes = series[key].rx_bytes + rx_bytes
      series[key].tx_bytes = series[key].tx_bytes + tx_bytes
      series[key].connections = series[key].connections + conns
    end
  end

  fh:close()

  for _, entry in pairs(series) do
    rx_metric(entry.labels, entry.rx_bytes)
    tx_metric(entry.labels, entry.tx_bytes)
    conns_metric(entry.labels, entry.connections)
  end
end

return {
  scrape = scrape
}
