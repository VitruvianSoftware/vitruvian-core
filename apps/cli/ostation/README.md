# Ostation 2 Pro — local LAN protocol notes & prototype

Working notes and a proven Python prototype for talking to the Olight Ostation 2 Pro
battery charger over its local LAN (no cloud). This is a prototype: the goal is to
iterate here, then implement a proper client in Rust (likely as a `homelab` CLI
subcommand or its own small tool).

## Device

| | |
|---|---|
| Model | Olight Ostation 2 Pro (3-in-1 battery charger) |
| IP | `192.168.86.70` (DHCP; confirmed by unplug/replug test) |
| MAC | `D8:FC:92:1F:9A:02` (OUI: Tuya Smart) |
| Device ID | `eb4ac75d7a3b46ecadoldi` |
| localKey | `^Jm[8&31gvy=XHu0` (16 bytes ASCII) |
| Open ports | TCP 6668 only (plus UDP 53/67 listeners that never answered discovery) |

The device is Tuya-based. The Olight app is an OEM Tuya app (`com.thingclips` SDK
visible in logcat). The localKey was extracted from the Android app via `adb logcat`
(see "Key extraction" below).

## Protocol: Tuya LAN 3.5 with an 18-byte header

This is stock Tuya protocol 3.5 **except** the 6699 message header is **18 bytes**,
not the 20 bytes tinytuya (and most libraries) assume:

```
offset  size  field
0       4     prefix      0x00006699
4       2     unknown     always 0x0000        <- 2 bytes, NOT 4
6       4     seqno       big-endian counter
10      4     cmd         big-endian command
14      4     length      big-endian, = len(iv) + len(ciphertext) + len(tag)
18      ...   payload     [12B GCM IV][ciphertext][16B GCM tag]
        4     suffix      0x00009966
```

- Encryption: AES-128-GCM with the localKey (handshake) or the derived session key
  (post-handshake).
- **AAD = header bytes 4..18** (the 14 bytes after the prefix: unknown + seqno + cmd +
  length). Getting this wrong fails tag verification with no error from the device.
- Plaintext lengths confirmed against a real capture: status request cmd 16 payload is
  12+2+16 = 30 wire bytes for plaintext `{}`.

> **Why tinytuya fails (error 914, silent device):** tinytuya packs/unpacks a 20-byte
> header (`>IHIII`, 4-byte unknown). Every frame it sends is misparsed by the device and
> every device frame misparsed by tinytuya. The device silently drops undecryptable
> frames — no error, just silence.

### Session-key negotiation (cmds 3 → 4 → 5)

1. **Client → device, cmd 3** (`SESS_KEY_NEG_START`): plaintext = 16 random bytes
   (`local_nonce`), encrypted with the **localKey**.
2. **Device → client, cmd 4** (`SESS_KEY_NEG_RESP`): plaintext = `retcode(4, 0x00000000)`
   + `remote_nonce(16)` + `hmac(32)`, encrypted with the localKey. The HMAC must equal
   `HMAC-SHA256(localKey, local_nonce)` — this is the key-verification step. (Observed
   remote nonces look like ASCII, e.g. `287799768a4a11c7`.)
3. **Client → device, cmd 5** (`SESS_KEY_NEG_FINISH`): plaintext =
   `HMAC-SHA256(localKey, remote_nonce)` (32 bytes), encrypted with the localKey.
4. **Session key** (tinytuya-compatible derivation):
   `AES-GCM(localKey, iv=local_nonce[:12]).encrypt(local_nonce XOR remote_nonce)[:16]`
   (first 16 bytes of the ciphertext).
5. All post-handshake frames (status, heartbeats) use the session key.

### Commands observed

| cmd | direction | meaning |
|-----|-----------|---------|
| 3   | c→d       | session-key negotiation start |
| 4   | d→c       | session-key negotiation response |
| 5   | c→d       | session-key negotiation finish |
| 9   | both      | heartbeat (every ~10s; plaintext-encrypted empty payload) |
| 16  | c→d / d→c | status request (`{}`) / status response (`{"dps": {...}}`) |

The device also emits zero-byte padding chunks on the TCP stream (e.g. `0x0000` after
connect, `0x000000000000` mid-handshake) — skip any leading zeros when parsing.

### Status DPS map (from the Ostation 2 community / tuya-local)

```json
{"dps": {"101": false, "102": 2, "103": false, "104": false,
         "105": 3, "106": false, "108": 0, "111": false, "113": 0}}
```

- `101` power/enable — `102` fully-charged count — `103`/`104`/`106` bin-full indicators
- `105` wake sensitivity — `108` invalid battery count — `111`/`112` schedule
- `110` per-bay telemetry (base64) — `113` diagnostic code

DP 110/112 did not appear in the standard status response; they likely need cmd 18
(`dpId` query) or arrive as push updates.

## Files

- `ostation_client.py` — working one-shot client: connect → negotiate → status. Runs
  under pycryptodome *or* `cryptography` (AESGCM).
- `ost_relay.py` — TCP relay `127.0.0.1:1999 → adb → phone nc → charger`. Needed
  because this Mac's Python gets `EHOSTUNREACH` to LAN IPs while `nc`/`ping` work
  (never root-caused); the relay sidesteps it.
- `ost_app.pcap` — captured Olight-app session (handshake + status + heartbeats), a
  ready-made regression fixture for a Rust implementation.

## Running it

The charger accepts a single LAN session at a time — force-stop the Olight app first
(`adb shell am force-stop com.olight.omall`) or it will silently ignore new clients.

```sh
# from a host on the LAN (e.g. the subnet-router node):
python3 ostation_client.py 192.168.86.70 6668

# from this Mac (Python can't reach LAN IPs directly; relay via the phone):
python3 ost_relay.py &          # adb wireless-debugging must be connected
python3 ostation_client.py 127.0.0.1 1999
```

## Key extraction (adb logcat, no root)

```sh
adb logcat -v raw -s Thing-Network:D Thing-Bluetooth:D Thing-Activator:D
# then launch the Olight app and open the Ostation page; look for:
# [ConnectDeviceWithHandShake:1133]localkey: ^Jm[8&31gvy=XHu0
```

The handshake log lines are a goldmine: `[LogHexData:60]data:` logs the first bytes of
each outgoing encrypted payload, and after `GetSessionKey` the `SendByte2:448` line logs
the derived binary session key — both were used to verify the analysis offline.

## Rust implementation notes (next step)

- The framing is simple enough that no Tuya library is needed: a Rust client needs
  `tokio`/`std` TCP + `aes-gcm` crate + `hmac`/`sha2`. The whole protocol is ~150 lines.
- Parse strictly per the 18-byte header above; skip zero padding between frames.
- Keep the localKey out of source long-term: load from config/env (it is committed here
  only as scratchpad reference; it is a LAN-only credential).
- Test fixture: replay `ost_app.pcap` frames through the Rust decoder and compare
  plaintexts with the values recorded in this README.
