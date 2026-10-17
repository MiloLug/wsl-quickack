# wsl-quickack

Removes a 40 ms stall from TCP connections that WSL makes to Windows under mirrored networking.

With `networkingMode=mirrored`, a request/response protocol between a WSL client and a Windows
service can take ~44 ms per exchange over a link whose round trip is 0.2 ms. `wsl-quickack`
sets `quickack 1` on the routes WSL uses to reach Windows, and keeps it there.

Measured on one machine (a gdb-remote client in WSL, Apple Mobile Device Service on Windows):
small request/response round trip **44 ms → 1.6 ms**, Linux delayed ACKs per 40 exchanges
**+72 → 0**.

## Why the stall happens

1. When a Windows service answers with a few small writes, Windows' Nagle algorithm sends the
   first one and holds the rest until the first is acknowledged.
2. Linux has nothing to send back on that connection, so it delays its ACK, hoping to piggyback
   it on data. The minimum delay is 40 ms.
3. So each small reply waits for Linux's delayed-ACK timer: 40 ms plus the real transfer time.
   Replies of a full segment (1448 bytes here) aren't held by Nagle, which makes the effect
   look intermittent.

The client can't fix it with `TCP_NODELAY` (that only stops its own Nagle) or `TCP_QUICKACK`
(Linux turns it back off after a few segments). The socket that waits isn't always the
client's either, e.g. behind a relay like socat.

You'll see it as `TcpExtDelayedACKs` rising by about one per exchange:

```sh
nstat -az TcpExtDelayedACKs
```

## What it does

In mirrored mode, `ip rule` sends traffic for Windows through extra routing tables: `127` for
`127.0.0.1` (localhost forwarding) and `128` for Windows' own addresses. `quickack 1` on a route
makes Linux ACK immediately on every connection over that route, including connections that are
already open.

WSL rebuilds those tables on boot and network changes, which drops the flag. So `wsl-quickack
watch` sets it, then listens to `ip monitor route` and sets it again after every rebuild. It's
event-driven, not polled, and uses only bash and iproute2.

```
wsl-quickack status   # each route, on/off; exit 0 when all are on, 2 when no tables are found
wsl-quickack apply    # set quickack on every route in those tables (root)
wsl-quickack watch    # apply, then again on every route change (root; what the service runs)
```

## Install

```sh
sudo make install                  # /usr/local/sbin/wsl-quickack + /etc/systemd/system/wsl-quickack.service
sudo systemctl daemon-reload
sudo systemctl enable --now wsl-quickack
wsl-quickack status
```

`PREFIX`, `SBINDIR`, `UNITDIR` and `DESTDIR` work as usual. Remove it with
`sudo systemctl disable --now wsl-quickack && sudo make uninstall`. The routes keep the flag
until WSL rebuilds them.

Needs systemd in WSL (`[boot] systemd=true` in `/etc/wsl.conf`).

## Limits

- Mirrored networking only. With NAT networking there are no such tables, and `status` exits 2.
- Only connections WSL opens to Windows. The reverse direction (a Windows client of a WSL
  service) depends on Windows' delayed ACK, which can't be changed from WSL.
- Linux then sends one ACK per received segment on these routes instead of one per two or per
  40 ms. On a link with a sub-millisecond round trip that's negligible.

## License

MIT, see [LICENSE](LICENSE).
