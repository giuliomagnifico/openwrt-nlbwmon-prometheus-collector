# OpenWrt nlbwmon Prometheus collector

A lightweight Prometheus collector for OpenWrt that exports `nlbwmon` traffic accounting data through `prometheus-node-exporter-lua`.

It exposes per-host traffic metrics with labels for IP address, MAC address, hostname, protocol, port and Layer 7 protocol.

<img width="2952" height="530" alt="Safari 02-07-2026 at 16 22 38" src="https://github.com/user-attachments/assets/42a6e3dc-8f54-4244-bcfb-913db0c423b2" />


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

wget -O /usr/lib/lua/prometheus-collectors/nlbwmon.lua https://raw.githubusercontent.com/giuliomagnifico/openwrt-nlbwmon-prometheus-collector/main/collectors/nlbwmon.lua && /etc/init.d/prometheus-node-exporter-lua restart

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
nlbwmon_rx_bytes{hostname="example-host",ip="192.168.1.100",mac="aa:bb:cc:dd:ee:ff",proto="TCP",family="4",layer7="HTTPS",port="443"} 123456789

```

## Prometheus scrape config

If you already scrape `prometheus-node-exporter-lua`, no extra target is needed.


## Example PromQL queries

Total traffic by host:

```promql

topk(20, sum by(hostname, ip) (

  nlbwmon_rx_bytes{hostname=~".+"}

  +

  nlbwmon_tx_bytes{hostname=~".+"}

))

```

Traffic in the last 24 hours:

```promql

topk(20, sum by(hostname, ip) (

  increase(nlbwmon_rx_bytes{hostname=~".+"}[24h])

  +

  increase(nlbwmon_tx_bytes{hostname=~".+"}[24h])

))

```

Download by host in the last 24 hours:

```promql

topk(20, sum by(hostname, ip) (

  increase(nlbwmon_rx_bytes{hostname=~".+"}[24h])

))

```

Upload by host in the last 24 hours:

```promql

topk(20, sum by(hostname, ip) (

  increase(nlbwmon_tx_bytes{hostname=~".+"}[24h])

))

```

Traffic by Layer 7 protocol in the last 24 hours:

```promql

topk(20, sum by(layer7) (

  increase(nlbwmon_rx_bytes{hostname=~".+"}[24h])

  +

  increase(nlbwmon_tx_bytes{hostname=~".+"}[24h])

))

```

DNS traffic by host in the last 24 hours:

```promql

topk(20, sum by(hostname, ip) (

  increase(nlbwmon_rx_bytes{hostname=~".+", layer7="DNS"}[24h])

  +

  increase(nlbwmon_tx_bytes{hostname=~".+", layer7="DNS"}[24h])

))

```

Real-time traffic rate by host:

```promql

topk(20, sum by(hostname, ip) (

  rate(nlbwmon_rx_bytes{hostname=~".+"}[5m])

  +

  rate(nlbwmon_tx_bytes{hostname=~".+"}[5m])

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

`nlbwmon` resets its accounting period according to its OpenWrt configuration.

For example, if `nlbwmon` is configured to restart every first day of the month, the cumulative metrics also reset monthly.

Prometheus or Mimir may keep old time series after label changes. Use this selector to exclude older series without the `hostname` label:

```promql

{hostname=~".+"}

```
