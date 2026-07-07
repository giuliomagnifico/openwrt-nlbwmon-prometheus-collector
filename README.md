# OpenWrt nlbwmon Prometheus collector

A lightweight Prometheus collector for OpenWrt that exports `nlbwmon` traffic accounting data through `prometheus-node-exporter-lua`.

It exposes per-host traffic metrics with labels for IP address, MAC address, hostname, protocol, port and Layer 7 protocol.

<img width="2444" height="2144" alt="Safari 07-07-2026 at 06 23 05" src="https://github.com/user-attachments/assets/7910a97f-67ac-4a5d-8d3f-472fdfd15e01" />

## Metrics

The collector exports:

```text
nlbwmon_rx_bytes
nlbwmon_tx_bytes
nlbwmon_connections
```

Labels:

```text
family
proto
port
mac
ip
hostname
layer7
```

Hostnames are resolved from:

1. OpenWrt static DHCP host entries from `uci show dhcp`

2. `/tmp/dhcp.leases`

3. The IP address itself as fallback

## Installation

Copy the collector to the Prometheus Lua collectors directory:

```sh
wget -O /usr/lib/lua/prometheus-collectors/nlbwmon.lua https://raw.githubusercontent.com/giuliomagnifico/openwrt-nlbwmon-prometheus-collector/main/nlbwmon.lua && /etc/init.d/prometheus-node-exporter-lua restart
```

Test the collector:

```sh
wget -qO- 'http://127.0.0.1:9100/metrics?collect[]=nlbwmon' | grep nlbwmon | head
```

You should see output similar to:

```text
# TYPE nlbwmon_rx_bytes gauge
# TYPE nlbwmon_tx_bytes gauge
# TYPE nlbwmon_connections gauge
nlbwmon_connections{mac="a8:5b:78:07:d0:5a",proto="UDP",hostname="iPad-bagno",family="4",layer7="mDNS",port="5353",ip="192.168.50.194"} 139
```

## Prometheus scrape config

If you already scrape `prometheus-node-exporter-lua`, no extra target is needed.

## Example PromQL queries

For time-based panels, use Grafana's query options instead of hardcoding the range in PromQL queries.

Recommended Grafana query options:

```text
Query options → Relative time: 1h / 24h / 7d / 30d
Query options → Time shift: empty
```

Use `$__range` inside `increase()` so the PromQL query automatically follows the panel relative time or dashboard time range.

### Total cumulative traffic by host

This shows the current cumulative `nlbwmon` accounting period, for example the current month if `nlbwmon` resets monthly.

```promql
topk(20, sum by(hostname, ip) (
  nlbwmon_rx_bytes{hostname=~".+"}
  +
  nlbwmon_tx_bytes{hostname=~".+"}
))
```

### Total traffic by host over the selected Grafana time range

Use this for panels such as "Last 1 hour", "Last 24 hours", "Last 7 days", etc.

```promql
topk(20, sum by(hostname, ip) (
  increase(nlbwmon_rx_bytes{hostname=~".+"}[$__range])
  +
  increase(nlbwmon_tx_bytes{hostname=~".+"}[$__range])
))
```

### Download by host over the selected Grafana time range

```promql
topk(20, sum by(hostname, ip) (
  increase(nlbwmon_rx_bytes{hostname=~".+"}[$__range])
))
```

### Upload by host over the selected Grafana time range

```promql
topk(20, sum by(hostname, ip) (
  increase(nlbwmon_tx_bytes{hostname=~".+"}[$__range])
))
```

### Traffic by Layer 7 protocol over the selected Grafana time range

```promql
topk(20, sum by(layer7) (
  increase(nlbwmon_rx_bytes{hostname=~".+"}[$__range])
  +
  increase(nlbwmon_tx_bytes{hostname=~".+"}[$__range])
))
```

### DNS traffic by host over the selected Grafana time range

```promql
topk(20, sum by(hostname, ip) (
  increase(nlbwmon_rx_bytes{hostname=~".+", layer7="DNS"}[$__range])
  +
  increase(nlbwmon_tx_bytes{hostname=~".+", layer7="DNS"}[$__range])
))
```

### Real-time traffic rate by host

Use this for time series panels showing current bandwidth usage.

```promql
topk(20, sum by(hostname, ip) (
  rate(nlbwmon_rx_bytes{hostname=~".+"}[$__rate_interval])
  +
  rate(nlbwmon_tx_bytes{hostname=~".+"}[$__rate_interval])
) * 8)
```

## Grafana units

Use this unit for total traffic panels:

```text
bytes(IEC)
```

Use this unit for `rate()` queries:

```text
bits/sec
```

Recommended panel types for total traffic:

- Pie chart
- Bar gauge
- Table
- Stat

Recommended panel type for real-time traffic rate:

- Time series

## Notes

`$__range` follows the dashboard time range or the panel `Relative time` option.

Examples:

```text
Relative time: 1h   → $__range = 1h
Relative time: 24h  → $__range = 24h
Relative time: 7d   → $__range = 7d
```

`Time shift` should usually be left empty unless you explicitly want to compare with a previous period.

`nlbwmon` resets its accounting period according to its OpenWrt configuration. For example, if `nlbwmon` is configured to restart every first day of the month, the cumulative metrics also reset monthly.

Prometheus or Mimir may keep old time series after label changes. Use this selector to exclude older series without the `hostname` label:

```promql
{hostname=~".+"}
```
