# BLE Advertise Failure - Root Cause & Fix Plan (2026-02-24)

## Scope
- Project: BLEBeaconTool
- Area: `advertise` command behavior on macOS
- Goal: determine why advertising reports success but is not detected as a real iBeacon

## Findings (Code Review)

### 1) Current iBeacon path always reports success when CoreBluetooth accepts the call
- `EnhancediBeaconStrategy` builds iBeacon-style manufacturer data and calls `CBPeripheralManager.startAdvertising`.
- Success is based on `peripheralManagerDidStartAdvertising(..., error: nil)` only.
- There is no verification step confirming the over-the-air packet still contains Apple iBeacon manufacturer data.

Impact:
- The CLI can print "Broadcasting iBeacon successfully" even when emitted packets are not valid iBeacon frames for receivers.

### 2) Existing project evidence already matches macOS platform restriction behavior
- `Docs/BLE_TROUBLESHOOTING_2026-02-20.md` documents that on macOS, manufacturer data for iBeacon is stripped/blocked in this path.
- This aligns with observed behavior: scanner works, advertise appears successful, but peers do not see valid iBeacon.

### 3) Fallback strategy exists but is not used for advertise by default
- `GATTServiceStrategy` provides a non-iBeacon BLE advertisement mode.
- `main.swift` currently hardcodes `EnhancediBeaconStrategy` for `advertise` and does not auto-fallback or fail fast with a clear platform message.

## Root Cause (Most Likely)
The primary failure is not a simple missing permission prompt. The current advertise flow uses a path that can return success callbacks while not producing standards-compliant iBeacon packets on macOS.

In short:
- Scanner issue was code/run-loop/API related and is fixed.
- Advertise issue is platform capability mismatch + missing runtime guardrails in app logic.

## Fix Plan (Prioritized)

## Phase 1 - Correctness & UX (high priority)
1. Add explicit macOS iBeacon capability guard in advertise startup.
   - Before starting iBeacon advertise, detect platform limitation and stop with a clear actionable error.
2. Replace optimistic success message.
   - Do not print iBeacon success unless strategy is actually iBeacon-capable on this platform.
3. Return structured `BeaconError.advertisingRestricted` with precise recovery text.
   - Suggest alternatives: use iPhone/hardware beacon for real iBeacon broadcast.

Acceptance criteria:
- On affected macOS, `advertise` exits with deterministic, explicit message instead of false success.

## Phase 2 - Strategy routing (high priority)
1. Add strategy selection in `main.swift`.
   - Use `SystemCapabilityDetector.recommendStrategy()` or explicit guard logic.
2. If iBeacon is restricted, either:
   - A) Fail fast (strict mode, default), or
   - B) Fallback to `GATTServiceStrategy` when user passes `--allow-gatt-fallback`.
3. Print final selected mode at startup (`iBeacon` vs `GATT fallback`).

Acceptance criteria:
- Runtime strategy is explicit and reproducible.
- No silent downgrade.

## Phase 3 - Verification tooling (medium priority)
1. Add an integration check command (or debug flag) that validates observed advertise payload via a second scanner path.
2. Add negative test expectation for macOS iBeacon advertise path:
   - Ensure command fails with `advertisingRestricted` in strict iBeacon mode.
3. Add positive test for GATT fallback mode.

Acceptance criteria:
- CI/local tests prevent regression to false-positive advertise success.

## Phase 4 - Documentation updates (medium priority)
1. Update `README.md` advertise section:
   - Clearly state macOS limitations for real iBeacon transmission.
2. Add examples:
   - strict iBeacon mode failure sample
   - optional GATT fallback sample
3. Link troubleshooting and architecture decision.

Acceptance criteria:
- User expectations match actual platform behavior before running command.

## Security/Quality Notes
- No secret handling changes required.
- Avoid suggesting `sudo` as a primary fix for platform restrictions.
- Keep behavior deterministic and auditable via explicit errors.

## Suggested Next Implementation Order
1. Capability guard + fail-fast error messaging
2. Strategy selection/fallback CLI option
3. Tests for strict/fallback flows
4. README/docs alignment

## Implementation Risk
- Low code risk, moderate product expectation risk.
- Main risk is user confusion if fallback behavior is implicit; mitigate with explicit mode output.
