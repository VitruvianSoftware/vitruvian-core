# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Offline tests for the Ostation framing: no charger needed.

Round-trips frames through the client's own pack_frame/Reader over a socket pair,
which pins the 18-byte header, the GCM AAD, and zero-padding skipping.
"""

import socket
import struct

import pytest

import ostation_client as oc


@pytest.fixture
def pair():
    a, b = socket.socketpair()
    yield a, b
    a.close()
    b.close()


def test_header_is_18_bytes_and_carries_fields(pair):
    tx, rx = pair
    frame = oc.pack_frame(7, 16, b"{}", oc.LOCAL_KEY)
    assert frame[:4] == oc.PREFIX
    assert frame[4:6] == b"\x00\x00"
    seqno, cmd, length = struct.unpack(">III", frame[6:18])
    assert (seqno, cmd) == (7, 16)
    assert length == len(frame) - 18 - 4
    assert frame[-4:] == oc.SUFFIX


def test_frame_round_trips_through_reader(pair):
    tx, rx = pair
    tx.sendall(oc.pack_frame(3, 16, b'{"dps":{}}', oc.LOCAL_KEY))
    seqno, cmd, pt = oc.Reader(rx).read_frame()
    assert (seqno, cmd, pt) == (3, 16, b'{"dps":{}}')


def test_zero_padding_before_a_frame_is_skipped(pair):
    tx, rx = pair
    tx.sendall(b"\x00\x00" + b"\x00" * 6 + oc.pack_frame(4, 9, b"", oc.LOCAL_KEY))
    seqno, cmd, pt = oc.Reader(rx).read_frame()
    assert (seqno, cmd, pt) == (4, 9, b"")


def test_tampered_header_fails_authentication(pair):
    tx, rx = pair
    frame = bytearray(oc.pack_frame(5, 16, b"{}", oc.LOCAL_KEY))
    frame[11] ^= 0x01  # flip a bit in the seqno, which is AAD
    tx.sendall(bytes(frame))
    with pytest.raises(Exception):
        oc.Reader(rx).read_frame()
