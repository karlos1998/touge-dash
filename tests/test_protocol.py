import unittest

from emu_dash.protocol import CHANNELS, FrameParser, TelemetryStore, encode_frame, raw_from_value


class FrameParserTest(unittest.TestCase):
    def test_fragmented_frames(self):
        parser = FrameParser()
        packet = encode_frame(1, 4321) + encode_frame(5, 511)
        frames = []
        for byte in packet:
            frames.extend(parser.feed(bytes([byte])))
        self.assertEqual([(f.channel, f.raw_value) for f in frames], [(1, 4321), (5, 511)])

    def test_recovers_after_noise_and_bad_checksum(self):
        parser = FrameParser()
        damaged = bytearray(encode_frame(3, 80))
        damaged[-1] ^= 0xFF
        frames = parser.feed(b"noise" + damaged + encode_frame(24, 92))
        self.assertEqual([(f.channel, f.raw_value) for f in frames], [(24, 92)])
        self.assertGreater(parser.dropped_bytes, 0)
        self.assertGreater(parser.bad_checksums, 0)

    def test_signed_and_scaled_channels(self):
        self.assertEqual(CHANNELS[4].decode(raw_from_value(4, -20)), -20)
        self.assertEqual(CHANNELS[24].decode(raw_from_value(24, -12)), -12)
        self.assertAlmostEqual(CHANNELS[5].decode(raw_from_value(5, 13.8)), 13.8, places=1)
        self.assertAlmostEqual(CHANNELS[28].decode(raw_from_value(28, 123)), 123, places=0)

    def test_store_derives_boost_and_cel(self):
        parser = FrameParser()
        store = TelemetryStore()
        for frame in parser.feed(encode_frame(2, 201) + encode_frame(14, 101) + encode_frame(255, 0b101)):
            store.apply(frame)
        data = store.snapshot()
        self.assertAlmostEqual(data["boost_bar"], 1.0)
        self.assertEqual(data["cel_names"], ["CLT", "MAP"])


if __name__ == "__main__":
    unittest.main()

