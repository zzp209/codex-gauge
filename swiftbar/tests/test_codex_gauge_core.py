import unittest

from codex_gauge_core import classify_window, parse_jsonl


WEEKLY_ONLY = """\
{"timestamp":"2026-07-23T10:16:49.592Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":49.0,"window_minutes":10080,"resets_at":1785287160}}}}
"""

SPARK_AFTER_MAIN = """\
{"timestamp":"2026-07-23T10:16:40Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":40.0,"window_minutes":10080,"resets_at":1785287160}}}}
{"timestamp":"2026-07-23T10:16:50Z","payload":{"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1785300000}}}}
"""

OVERUSED = """\
{"timestamp":"2026-07-23T10:16:49Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":120.0,"window_minutes":300,"resets_at":1785287160}}}}
"""


class CodexGaugeCoreTests(unittest.TestCase):
    def test_weekly_primary_is_not_five_hour(self):
        snapshot = parse_jsonl(WEEKLY_ONLY)
        self.assertEqual(snapshot["windows"][0]["kind"], "weekly")
        self.assertEqual(snapshot["windows"][0]["remaining"], 51)

    def test_spark_limit_does_not_replace_main_codex(self):
        snapshot = parse_jsonl(SPARK_AFTER_MAIN)
        self.assertEqual(snapshot["limit_id"], "codex")
        self.assertEqual(snapshot["windows"][0]["remaining"], 60)

    def test_remaining_is_clamped(self):
        self.assertEqual(parse_jsonl(OVERUSED)["windows"][0]["remaining"], 0)

    def test_classifies_custom_window(self):
        self.assertEqual(classify_window(300), "five_hour")
        self.assertEqual(classify_window(10_080), "weekly")
        self.assertEqual(classify_window(1_440), "custom")


if __name__ == "__main__":
    unittest.main()
