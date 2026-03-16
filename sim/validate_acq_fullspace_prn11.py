#!/usr/bin/env python3
"""Fixed-PRN cross-check wrapper for full-space acquisition validation."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    verify_script = Path(__file__).with_name("verify_acq_fft_crosscheck.py")
    cmd = [sys.executable, str(verify_script), "--prn", "11", *sys.argv[1:]]
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
