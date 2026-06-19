# CI Pipeline Validation Report

**Repository:** `ayushsoni-itgeeks/ci-testing3`
**Pipeline:** Security & Quality Pipeline (`.github/workflows/main.yml`)
**Date:** 2026-06-19
**Driver:** PR #5 (branch `ci-selftest` → `main`), force-pushed once per test
**Outcome:** ✅ **7 / 7 tests passed — pipeline behaves exactly as designed**

---

## 1. Purpose

Verify that the CI pipeline (a) **blocks** every category of bad input it claims to
catch and (b) **does not** raise false positives on safe input. Each test isolated a
single detection path by resetting the branch to clean `main` before planting one
artifact, so results never contaminated each other.

## 2. Pipeline under test

A 4-job GitHub Actions workflow with a staged short-circuit — each stage only runs if
the previous one is clean, and a single **Security Gate** makes the merge decision.

| Stage | Check | Blocks merge on |
|-------|-------|-----------------|
| 1 · Secrets & Credentials | Gitleaks, TruffleHog, `.env` files, private-key files (by name), private-key material (PEM content) | any finding |
| 2 · Dependencies & Vulnerabilities | npm audit, Trivy (vuln/secret/misconfig/license) | critical/high npm vuln **or** Trivy critical/high |
| 3 · Static Code Analysis | ESLint, TypeScript (`tsc --noEmit`), Prettier | ESLint **error** or TypeScript error (Prettier/warnings non-blocking) |
| Report · Security Gate | aggregates all stages | any blocking finding above |

## 3. Test matrix & results

| # | Test | Input planted | Expected | Actual | Run | Verdict |
|---|------|---------------|----------|--------|-----|---------|
| 1 | Private-key **content** | file with a PEM `PRIVATE KEY` block (`config/app-credentials.txt`) | FAIL Stage 1 — Gitleaks + PEM scan | FAIL — 3 findings: 1 Gitleaks `private-key` + 2 PEM rows (source + merge commit) | #27818035601 | ✅ |
| 2 | Private-key **filename** | `deploy/server.key` with **non-PEM** dummy content | FAIL Stage 1 — key-file check only | FAIL — 1 finding: `deploy/server.key`; Gitleaks/PEM/env all clean | #27818116678 | ✅ |
| 3 | Committed **.env** | `.env` (force-added) **plus** `.env.example` | FAIL — `.env` flagged, `.env.example` excluded | FAIL — 1 finding: `.env` only; `.env.example` correctly not listed | #27818229174 | ✅ |
| 4 | **Negative control** | `pub.txt` (public key) + `.env.example` only | PASS Stage 1 → proceed to 2 & 3 | PASS — 0 findings; all 3 stages ran; merge allowed | #27818358377 | ✅ |
| 5 | Vulnerable **dependency** | `axios@0.21.1` pinned (lockfile updated) | FAIL Stage 2 — npm + Trivy | FAIL — 12 blocking: 1 npm high + 11 Trivy HIGH CVEs; Stage 3 skipped | #27818593115 | ✅ |
| 6 | **TypeScript error** | `app/selftest-typeerror.ts` (TS2322) | FAIL Stage 3 — tsc | FAIL — 1 TypeScript error; ESLint clean; Stages 1 & 2 passed | #27818738611 | ✅ |
| 7 | **Clean change** | trivial README comment | PASS all stages — merge allowed | PASS — 0 blocking, all stages green | #27818855028 | ✅ |

## 4. Detailed findings

### Test 1 — Private-key content (Stage 1)
- **Result:** FAILED — merge blocked · Stage 1 FAIL, Stages 2 & 3 SKIP.
- **Findings (3):** Gitleaks `private-key` at `config/app-credentials.txt:2`; PEM-material scan reported the file in **two** commits (the source commit + the GitHub PR-merge commit).
- **Note:** Demonstrates the content scan counts **one row per commit** the key appears in — hence 3 total, not 1.

### Test 2 — Private-key by filename (Stage 1)
- **Result:** FAILED · Stage 1 FAIL.
- **Findings (1):** "Private key files (tree + history)" → `deploy/server.key`. Gitleaks, PEM, `.env`, TruffleHog all clean.
- **Note:** Proves the filename detector catches key files **even when contents aren't recognizable key material**, and counts **unique paths** (1, not doubled by the merge commit).

### Test 3 — Committed `.env` (Stage 1)
- **Result:** FAILED · Stage 1 FAIL.
- **Findings (1):** Committed `.env` files → `.env`. `.env.example` was **not** flagged.
- **Note:** Confirms both the `.env` detector and its example-file exclusion. `.env` is gitignored, so it was force-committed to simulate a real bypass.

### Test 4 — Negative control (Stage 1)
- **Result:** PASSED — merge allowed · all 3 stages ran.
- **Findings:** none in Stage 1. Public key (`pub.txt`) and `.env.example` correctly ignored.
- **Note:** First run to clear Stage 1, confirming the repo baseline is healthy (0 critical/high vulns, 0 ESLint/TS errors). 297 non-blocking warnings (license notes, outdated packages, 1 medium misconfig).

### Test 5 — Vulnerable dependency (Stage 2)
- **Result:** FAILED — merge blocked · Stage 1 PASS, Stage 2 FAIL, Stage 3 SKIP.
- **Findings (12 blocking):** npm audit → axios (high); Trivy → 11 HIGH axios CVEs (e.g. CVE-2021-3749 ReDoS, CVE-2025-27152 SSRF).
- **Note:** Medium/low vulns and 284 license issues were correctly classified as **non-blocking** warnings.

### Test 6 — TypeScript error (Stage 3)
- **Result:** FAILED — merge blocked · Stages 1 & 2 PASS, Stage 3 FAIL.
- **Findings (1 blocking):** TypeScript `error TS2322` in `app/selftest-typeerror.ts`. ESLint clean, Prettier no blocking issue.
- **Note:** First run to reach Stage 3 — confirms the type-check gate.

### Test 7 — Fully clean change (control)
- **Result:** PASSED — merge allowed · all stages green.
- **Findings:** none blocking; 297 non-blocking warnings.
- **Note:** Proves the pipeline does not over-block legitimate changes.

## 5. Conclusions

- ✅ **Every blocking detector fires** on real bad input across all three stages.
- ✅ **No false positives** — public keys, `.env.example`, medium/low vulns, license
  notes, and outdated-package warnings are all correctly non-blocking.
- ✅ **Staged short-circuit works** — a failing stage skips later stages; a clean PR
  runs all three and passes.
- ✅ **Counting is correct** — content scan counts per-commit, file scan counts unique
  paths.

**The Security & Quality Pipeline is functioning as designed.**

## 6. Methodology notes / reproducibility

- All tests ran against **PR #5** (`ci-selftest` → `main`). The branch was reset to
  `origin/main` (`git reset --hard` + `git clean`) before each test, then one artifact
  was planted, committed, and force-pushed to re-trigger the run.
- `main` was never modified; all planted artifacts live only on `ci-selftest`.
- **Cleanup:** delete the test branch (auto-closes PR #5) with
  `git push origin --delete ci-selftest`.
