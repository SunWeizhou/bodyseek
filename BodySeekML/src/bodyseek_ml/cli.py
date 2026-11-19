"""Command-line entry point for BodySeekML offline pipelines."""

from __future__ import annotations

import argparse
from pathlib import Path
import time
from typing import Sequence

from .export_parser import parse_export_to_features
from .patterns import analyze_distributed_lag_patterns, render_personal_patterns_report


def run_m4a(export_zip: Path, out_dir: Path, report: Path) -> int:
    """Execute the full M4a offline pipeline: stream parse, dedup audit, distributed-lag patterns, and anonymized report."""
    t0 = time.perf_counter()
    df, spec, dedup_audit = parse_export_to_features(export_zip, out_dir)
    t_parse = time.perf_counter() - t0

    t1 = time.perf_counter()
    findings_payload = analyze_distributed_lag_patterns(df, out_dir)
    render_personal_patterns_report(
        df=df,
        dedup_audit=dedup_audit,
        findings_payload=findings_payload,
        report_path=report,
    )
    t_pat = time.perf_counter() - t1

    print(
        f"M4A_COMPLETE rows={len(df)} span={spec['date_range']['start_day_key']}..{spec['date_range']['end_day_key']} "
        f"sources={dedup_audit['total_distinct_sources']} "
        f"eligible_tests={findings_payload['eligible_tests']}/{findings_payload['total_tests']} "
        f"fdr_candidates={findings_payload['candidate_count']} "
        f"nominal={findings_payload['nominal_count']} "
        f"parse_s={t_parse:.2f}s pattern_s={t_pat:.2f}s"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="bodyseek-ml", description="BodySeek M4 offline modeling & audit CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    m4a = sub.add_parser("run-m4a", help="Run M4a HealthKit export feature pipeline and generate anonymized report")
    m4a.add_argument("--export-zip", required=True, type=Path, help="Path to Apple Health export .zip or .xml")
    m4a.add_argument("--out-dir", required=True, type=Path, help="Output directory for gitignored parquet/json artifacts")
    m4a.add_argument("--report", required=True, type=Path, help="Output path for anonymized Markdown pattern report")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "run-m4a":
        return run_m4a(args.export_zip, args.out_dir, args.report)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
