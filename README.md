# OpenWrt nlbwmon Prometheus collector

Prometheus collector for OpenWrt that exports `nlbwmon` traffic data using the `prometheus-node-exporter-lua`. It exposes per-host traffic metrics with labels for IP address, MAC, hostname, protocol, port and Layer 7 protocol.

## Example of a Dashboard 

<img width="2440" height="2132" alt="Safari 08-07-2026 at 06 18 35" src="https://github.com/user-attachments/assets/08311270-cae7-4c94-872b-1cb4fa8529c6" />


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

- OpenWrt static DHCP host entries from `uci show dhcp`

- `/tmp/dhcp.leases`

- The IP address as fallback

## Installation

Copy the collector to the Prometheus Lua collectors directory. Form your OpenWrt device:

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
nlbwmon_connections{mac="00:e0:99:00:0c:ff",proto="TCP",hostname="iPad-kiosk-eth",family="4",layer7="HTTPS",port="443",ip="192.168.1.12"} 2183
nlbwmon_rx_bytes{mac="10:a2:d3:e1:b2:f8",proto="TCP",hostname="Giulios-iPhone",family="4",layer7="HTTPS",port="443",ip="192.168.1.105"} 13415842630
```

## Example PromQL queries

For time-based panels, use Grafana's query options.

Recommended Grafana query options:

```text
Query options → Relative time: 1h / 24h / 7d / 30d
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

Use this for panels such as "Last 1 hour", "Last 24 hours", "Last 7 days", etc...

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


```promql
topk(20, sum by(hostname, ip) (
  rate(nlbwmon_rx_bytes{hostname=~".+"}[$__rate_interval])
  +
  rate(nlbwmon_tx_bytes{hostname=~".+"}[$__rate_interval])
) * 8)
```

## Grafana units

For traffic panels:

```text
bytes(IEC)
```

For `rate()` queries:

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


```text
Relative time: 1h   → $__range = 1h
Relative time: 24h  → $__range = 24h
Relative time: 7d   → $__range = 7d
```

`Time shift` should usually be left empty unless you explicitly want to compare with a previous period.

`nlbwmon` resets its accounting period according to its OpenWrt configuration. For example, if `nlbwmon` is configured to restart every first day of the month, the cumulative metrics also reset monthly.

```
root@R5S:~# uci show nlbwmon
nlbwmon.@nlbwmon[0]=nlbwmon
nlbwmon.@nlbwmon[0].netlink_buffer_size='10485760'
nlbwmon.@nlbwmon[0].commit_interval='12h'
nlbwmon.@nlbwmon[0].refresh_interval='5m'
nlbwmon.@nlbwmon[0].database_interval='1'
nlbwmon.@nlbwmon[0].protocol_database='/usr/share/nlbwmon/protocols'
nlbwmon.@nlbwmon[0].database_generations='0'
nlbwmon.@nlbwmon[0].database_limit='0'
nlbwmon.@nlbwmon[0].database_directory='/mnt/sda1/nlbwmon'
nlbwmon.@nlbwmon[0].local_network='192.168.0.0/16' '172.16.0.0/12' '10.0.0.0/8' '192.168.1.1/24' '192.168.2.1/24' '10.4.0.1/32' '192.168.50.1/24' '192.168.20.1/24' 'iot' 'wan' 'wg0'
```
