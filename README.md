# wsl-quickack

Removes a delayed-ACK stall from TCP connections that WSL makes to Windows under mirrored
networking, by keeping `quickack 1` on the routes WSL uses to reach Windows.

## Why it's needed

With `networkingMode=mirrored`, small request/response exchanges between a client in WSL and a
service on Windows stall on each reply, over a link whose round trip is 0.2 ms. Measured with a
gdb-remote client in WSL and Apple Mobile Device Service on Windows:

| | Without | With wsl-quickack |
|---|---|---|
| Small request/response round trip | 44 ms | 1.6 ms |
| Linux delayed ACKs per 40 exchanges | +72 | 0 |

The cause and how to check for it: [Why the stall happens](#why-the-stall-happens).

## Requirements

- WSL 2 with mirrored networking: `networkingMode=mirrored` in the `[wsl2]` section of
  `%UserProfile%\.wslconfig`.
- systemd in the distro: `systemd=true` in the `[boot]` section of `/etc/wsl.conf`.
- bash, iproute2, and make for the install.

Tested on Windows 10.0.26300, WSL 3.0.1.0 with kernel 6.18.40.1, iproute2 7.2.0, bash 5.3 and
systemd 262.

## Install

1. Install the script and the systemd unit:

   ```sh
   sudo make install
   ```

   This writes `/usr/local/sbin/wsl-quickack` and `/etc/systemd/system/wsl-quickack.service`.
   `PREFIX`, `SBINDIR`, `UNITDIR` and `DESTDIR` override the paths, for example
   `sudo make install PREFIX=/usr`.

2. Start the service and enable it on boot:

   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now wsl-quickack
   ```

3. Check that `wsl-quickack status` prints `on` for every route and exits 0.

To uninstall:

```sh
sudo systemctl disable --now wsl-quickack
sudo make uninstall
```

The routes keep `quickack 1` until WSL next rebuilds them.

## Usage

| Command | Needs root | What it does |
|---|---|---|
| `wsl-quickack status` | no | Prints each route as `on` or `off`. Exits 0 when all are on, 1 when any is off, 2 when no routes to Windows are found. |
| `wsl-quickack apply` | yes | Sets `quickack 1` once on every route that lacks it. |
| `wsl-quickack watch` | yes | Runs `apply`, then again on every route change. The service runs this. |

## Why the stall happens

Two TCP mechanisms wait on each other:

1. The Windows service answers with a few small writes. Windows' Nagle algorithm sends the
   first one and holds the rest until the first is acknowledged.
2. Linux has nothing to send back on that connection, so it delays its ACK, hoping to piggyback
   it on data. The minimum delay is 40 ms.
3. Each small reply therefore waits for Linux's delayed-ACK timer on top of the real transfer
   time. A reply of a full segment (1448 bytes on the measured link) is not held by Nagle, so
   the stall looks intermittent.

The client can't fix it from its own socket. `TCP_NODELAY` only stops the client's Nagle, and
Linux turns `TCP_QUICKACK` back off after a few segments. The socket that waits isn't always
the client's either, for example behind a relay such as socat. A one-off
`ip route change ... quickack 1` works until WSL rebuilds its routes.

### Check whether you're affected

`TcpExtDelayedACKs` rises by about one per exchange. The counter is system-wide, so other
traffic adds to it. Set a baseline, run the workload, then read the increase:

```sh
nstat -n
# run the WSL client against the Windows service
nstat -z TcpExtDelayedACKs
```

With wsl-quickack running, connections to Windows add nothing to it.

## How it works

In mirrored mode, `ip rule` sends traffic for Windows through extra routing tables: `127` for
`127.0.0.1` (localhost forwarding) and `128` for Windows' own addresses. The `quickack 1` route
attribute makes Linux ACK immediately on every connection over that route, including
connections that are already open.

WSL rebuilds those tables on boot and on network changes, which drops the attribute.
`wsl-quickack watch` sets it, then listens to `ip monitor route` and sets it again after every
rebuild, without polling. It uses only bash and iproute2, and covers IPv4 and IPv6.

## Troubleshooting

### `no routes to Windows found (is WSL networkingMode=mirrored?)`

`status` found no routing tables to Windows and exits 2. WSL is not in mirrored mode. Set
`networkingMode=mirrored` in `.wslconfig` and run `wsl --shutdown` from Windows to restart WSL.

### `status` shows `off` routes

The service is not running, or its last `apply` failed. `systemctl status wsl-quickack`
and `journalctl -u wsl-quickack` show why.

## Limits

- Only connections WSL opens to Windows. The reverse direction, a Windows client of a WSL
  service, depends on Windows' delayed ACK, which can't be changed from WSL.
- On these routes Linux sends one ACK per received segment instead of one per two segments or
  per delayed-ACK timeout. On a link with a sub-millisecond round trip that's negligible.
- It sets `quickack 1` on every table that `ip rule` looks up other than `local`, `main` and
  `default`. If you add your own policy-routing tables, their routes get it too.

## License

MIT, see [LICENSE](LICENSE).
