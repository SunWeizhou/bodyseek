"""Command-line entry point for BodySeekML offline pipelines (M4a + M4b-d)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import time
from typing import Sequence

import pandas as pd

from .coreml_export import fit_and_export_coreml
from .deep_models import render_m4c_report, run_m4c_comparison
from .export_parser import parse_export_to_features
from .forecasting import render_m4b_report, run_m4b_walk_forward
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


def run_m4bcd(parquet_path: Path, out_dir: Path, docs_dir: Path, kit_dir: Path) -> int:
    """Execute M4b walk-forward backtest, M4c deep comparison, and M4d CoreML export + parity artifacts."""
    t0 = time.perf_counter()
    df = pd.read_parquet(parquet_path)

    m4b_payload = run_m4b_walk_forward(df)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "m4b_backtest.json").write_text(json.dumps(m4b_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    render_m4b_report(m4b_payload, docs_dir / "validation" / "m4b-forecasting-backtest-2026-11-20.md")

    m4c_payload = run_m4c_comparison(df, m4b_payload)
    (out_dir / "m4c_comparison.json").write_text(json.dumps(m4c_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    render_m4c_report(m4c_payload, docs_dir / "validation" / "m4c-deep-model-comparison-2026-11-20.md")

    export_info = fit_and_export_coreml(
        df=df,
        m4b_payload=m4b_payload,
        m4c_payload=m4c_payload,
        kit_dir=kit_dir,
        docs_dir=docs_dir,
    )
    elapsed = time.perf_counter() - t0
    print(
        f"M4BCD_COMPLETE rows={len(df)} coreml_rel_err={export_info['max_python_coreml_rel_err']:.2e} "
        f"mlpackage={export_info['mlpackage_path']} elapsed_s={elapsed:.2f}s"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="bodyseek-ml", description="BodySeek M4 offline modeling & audit CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    m4a = sub.add_parser("run-m4a", help="Run M4a HealthKit export feature pipeline and generate anonymized report")
    m4a.add_argument("--export-zip", required=True, type=Path, help="Path to Apple Health export .zip or .xml")
    m4a.add_argument("--out-dir", required=True, type=Path, help="Output directory for gitignored parquet/json artifacts")
    m4a.add_argument("--report", required=True, type=Path, help="Output path for anonymized Markdown pattern report")

    m4bcd = sub.add_parser("run-m4bcd", help="Run M4b walk-forward, M4c deep comparison, and M4d CoreML export")
    m4bcd.add_argument("--parquet", required=True, type=Path, help="Path to M4a daily_features.parquet")
    m4bcd.add_argument("--out-dir", required=True, type=Path, help="Directory for gitignored backtest JSONs")
    m4bcd.add_argument("--docs-dir", required=True, type=Path, help="Repository docs/ root directory")
    m4bcd.add_argument("--kit-dir", required=True, type=Path, help="Repository BodySeekKit/ root directory")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "run-m4a":
        return run_m4a(args.export_zip, args.out_dir, args.report)
    if args.command == "run-m4bcd":
        return run_m4bcd(args.parquet, args.out_dir, args.docs_dir, args.kit_dir)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
