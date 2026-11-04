#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Olight Ostation 2 Pro - Tuya LAN protocol 3.5 client (18-byte header variant).

The Ostation's Tuya firmware uses a 6699 header of 18 bytes:
    prefix(4) + unknown(2) + seqno(4) + cmd(4) + length(4)
instead of the standard 20-byte header (4-byte unknown field). Payload layout is
stock 3.5: [12B GCM IV][ciphertext][16B tag], AAD = header bytes 4..18.

Usage: ostation_client.py [host] [port]
"""

import hashlib
import hmac
import json
import os
import socket
import struct
import sys

DEV_ID = "eb4ac75d7a3b46ecadoldi"
LOCAL_KEY = b"^Jm[8&31gvy=XHu0"
PREFIX = b"\x00\x00\x66\x99"
SUFFIX = b"\x00\x00\x99\x66"

try:
    from Crypto.Cipher import AES  # pycryptodome

    if not hasattr(AES, "MODE_GCM"):
        raise ImportError("pycrypto without GCM")

    def gcm_seal(key, iv, pt, aad):
        """Returns ciphertext || tag."""
        c = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=16)
        if aad:
            c.update(aad)
        return c.encrypt(pt) + c.digest()

    def encrypt_payload(key, raw, aad):
        iv = os.urandom(12)
        return iv + gcm_seal(key, iv, raw, aad)

    def decrypt_payload(key, iv, ct, tag, aad):
        c = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=16)
        if aad:
            c.update(aad)
        return c.decrypt_and_verify(ct, tag)

except ImportError:
    # Optional fallback backend; not a Bazel dep, hence the gazelle:ignore.
    from cryptography.hazmat.primitives.ciphers.aead import (
        AESGCM,
    )  # gazelle:ignore cryptography

    def gcm_seal(key, iv, pt, aad):
        return AESGCM(key).encrypt(iv, pt, aad)

    def encrypt_payload(key, raw, aad):
        iv = os.urandom(12)
        return iv + gcm_seal(key, iv, raw, aad)

    def decrypt_payload(key, iv, ct, tag, aad):
        return AESGCM(key).decrypt(iv, ct + tag, aad)


def pack_frame(seqno, cmd, raw, key):
    enc = encrypt_payload(
        key, raw, b"\x00\x00" + struct.pack(">III", seqno, cmd, 12 + len(raw) + 16)
    )
    length = len(enc)
    header = PREFIX + b"\x00\x00" + struct.pack(">III", seqno, cmd, length)
    return header + enc + SUFFIX


class Reader:
    """Reads 6699 frames from a socket, skipping zero padding the device emits."""

    def __init__(self, sock):
        self.sock = sock
        self.buf = b""

    def _recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def read_frame(self):
        while True:
            b = self._recv(4)
            if b != PREFIX:
                if b.strip(b"\x00"):
                    raise ValueError(f"unexpected stream bytes: {b.hex()}")
                continue  # device zero padding (e.g. b'\x00\x00', heartbeat acks)
            unknown, seqno, cmd, length = struct.unpack(">HIII", self._recv(14))
            payload = self._recv(length + 4)
            if payload[-4:] != SUFFIX:
                raise ValueError("bad suffix")
            enc = payload[:-4]
            iv, ct, tag = enc[:12], enc[12:-16], enc[-16:]
            pt = decrypt_payload(
                SESSION_KEY[0] if SESSION_KEY[0] else LOCAL_KEY,
                iv,
                ct,
                tag,
                b"\x00\x00" + struct.pack(">III", seqno, cmd, length),
            )
            return seqno, cmd, pt


SESSION_KEY = [None]


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "192.168.86.70"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 6668

    sock = socket.create_connection((host, port), timeout=10)
    sock.settimeout(10)
    r = Reader(sock)

    # --- session key negotiation (cmds 3/4/5), encrypted with the local key ---
    local_nonce = os.urandom(16)
    sock.sendall(pack_frame(1, 3, local_nonce, LOCAL_KEY))
    _, cmd, pt = r.read_frame()
    assert cmd == 4, f"expected step-2 cmd 4, got {cmd}"
    retcode, remote_nonce, hmac_dev = pt[:4], pt[4:20], pt[20:52]
    assert retcode == b"\x00\x00\x00\x00", f"step-2 retcode {retcode.hex()}"
    assert hmac.new(LOCAL_KEY, local_nonce, hashlib.sha256).digest() == hmac_dev, (
        "HMAC mismatch"
    )
    sock.sendall(
        pack_frame(
            2, 5, hmac.new(LOCAL_KEY, remote_nonce, hashlib.sha256).digest(), LOCAL_KEY
        )
    )

    # session key = GCM(localKey, iv=local_nonce[:12]).encrypt(nonce_xor)[0:16]
    xored = bytes(a ^ b for a, b in zip(local_nonce, remote_nonce))
    SESSION_KEY[0] = gcm_seal(LOCAL_KEY, local_nonce[:12], xored, None)[:16]
    print(f"session key: {SESSION_KEY[0].hex()}", file=sys.stderr)

    # --- status request (cmd 16); skip interleaved heartbeats (cmd 9) ---
    sock.sendall(pack_frame(3, 16, b"{}", SESSION_KEY[0]))
    while True:
        _, cmd, pt = r.read_frame()
        if cmd == 9:
            continue
        assert cmd == 16, f"expected status cmd 16, got {cmd}"
        print(json.dumps(json.loads(pt[4:]), indent=2))
        break
    sock.close()


if __name__ == "__main__":
    main()
