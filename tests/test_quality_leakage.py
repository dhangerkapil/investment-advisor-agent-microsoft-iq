"""The optimizer leakage guard: a candidate that copies test answers, absolute dates or staff names is not applied."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "evals"))
import foundry_quality as quality  # noqa: E402

TRUTH = ["NVDA is 26.1% of the portfolio ($763,857.78) as of October 19; the meeting is at 10:00 AM."]
STAFF = ["Alex Morgan", "Alex"]


def test_the_rejected_overfit_candidate_is_flagged():
    # The shape of the candidate the optimizer actually produced: a fixed date, the test's answers and a name.
    baseline = "Use rebalancing_check for every trim. Limits come from the signed IPS."
    candidate = baseline + "\nCurrent date is 2026-10-18. Michael's NVDA is 26.1% ($763,857.78). Greet Alex."
    findings = quality.leakage_findings(candidate, baseline, TRUTH, STAFF)
    assert any("absolute date" in finding for finding in findings)
    assert any("26.1%" in finding and "$763,857.78" in finding for finding in findings)
    assert any(finding == "names a staff member: Alex" for finding in findings)


def test_general_improvements_and_facts_already_in_the_baseline_pass():
    baseline = "Use rebalancing_check for every trim. The single-stock limit is in the IPS, for example 25%. Alex"
    candidate = baseline + "\nGroup sources by IQ. Keep the brief under 400 words. Quote the limit, for example 25%."
    assert quality.leakage_findings(candidate, baseline, TRUTH + ["The limit is 25%."], STAFF) == []
    assert quality.leakage_findings("Today is a good day to check sources.", "", TRUTH, STAFF) == []


def test_ground_truths_come_from_the_case_files():
    truths = quality.ground_truths()
    assert truths and all(isinstance(truth, str) and truth for truth in truths)
