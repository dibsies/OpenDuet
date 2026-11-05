#!/usr/bin/env python3
"""Validate the offline Duet II identifier USB setup fixture."""
import struct
import unittest

# Static trace in USB-PROTOCOL.md. No USB transport is used here.
SETUP = struct.Struct("<BBHHH")
IDENTIFIER_REQUEST = bytes.fromhex("c0 31 00 00 00 00 08 00")


def identifier_from_reply(reply):
    """Decode the 64-bit value used by the arm64 vendor identifier routine."""
    if len(reply) != 8:
        raise ValueError("Duet II identifier reply must be exactly eight bytes")
    return int.from_bytes(reply, "little")


class IdentifierFixtureTests(unittest.TestCase):
    def test_setup_packet(self):
        self.assertEqual(SETUP.pack(0xC0, 0x31, 0, 0, 8), IDENTIFIER_REQUEST)

    def test_reply_order(self):
        self.assertEqual(identifier_from_reply(bytes(range(1, 9))), 0x0807060504030201)

    def test_incomplete_or_oversized_reply(self):
        for size in (0, 7, 9):
            with self.subTest(size=size), self.assertRaises(ValueError):
                identifier_from_reply(bytes(size))


class InputControlFixtureTests(unittest.TestCase):
    def test_mode_is_zero_based(self):
        self.assertEqual(SETUP.pack(0x40, 0x16, 0, 0, 1), bytes.fromhex("40 16 00 00 00 00 01 00"))
        self.assertEqual(SETUP.pack(0x40, 0x16, 0, 1, 1), bytes.fromhex("40 16 00 00 01 00 01 00"))

    def test_phantom_is_zero_based(self):
        self.assertEqual(SETUP.pack(0x40, 0x15, 0, 0, 1), bytes.fromhex("40 15 00 00 00 00 01 00"))
        self.assertEqual(SETUP.pack(0x40, 0x15, 0, 1, 1), bytes.fromhex("40 15 00 00 01 00 01 00"))

    def test_gain_is_one_based(self):
        self.assertEqual(SETUP.pack(0x40, 0x34, 0, 1, 1), bytes.fromhex("40 34 00 00 01 00 01 00"))
        self.assertEqual(SETUP.pack(0x40, 0x3E, 0, 2, 1), bytes.fromhex("40 3e 00 00 02 00 01 00"))


if __name__ == "__main__":
    unittest.main()
