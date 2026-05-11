# AuraShift Build Hygiene

## Lightweight Cleanup
Use `scripts/cleanup-lite.sh` directly, or let it run automatically through:
- `scripts/build-local.sh`
- `scripts/test-local.sh`

The lightweight cleanup removes only conservative local artifacts:
- stale temporary workspace copies in `${TMPDIR}/aurashift-runner-workspaces` by default
- stale `.xcresult` bundles in `.aura-local/results` older than 3 days
- old local runner logs in `.aura-local/logs`
- obvious local temp or log markers at repo root created by the runner

The local wrappers run lightweight cleanup before each build or test cycle.

## Local Runner
Use these wrappers for conservative local build cycles:
- `scripts/build-local.sh`
- `scripts/test-local.sh`

The runner keeps logs and test result bundles inside `.aura-local`, but creates temporary workspace copies outside the repo by default at `${TMPDIR}/aurashift-runner-workspaces`. Keeping the copied workspace outside the source tree prevents the local copy flow from including its own destination during repeated builds.

Each runner workspace records the owner process ID and is removed with a shell `trap` when the command exits or is interrupted. If a prior runner shell dies unexpectedly, the next lightweight cleanup pass can prune that abandoned workspace copy.

`scripts/test-local.sh` now targets a dedicated simulator by default instead of guessing from any available device inventory:
- default simulator name: `AuraShift Local iPhone 16 Pro`
- default simulator type: `com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro`

If the dedicated simulator does not exist yet, the local runner creates it on the newest available iOS simulator runtime that supports that device type.

To avoid copying unnecessary heavy folders into each temporary workspace, the runner excludes:
- `.git/`
- `.aura-local/`
- `DerivedData/`
- `build/`
- `.build/`
- `Pods/`
- `Packages/`
- `*.xcresult/`
- `xcuserdata/`

The local wrappers also disable codesigning for these simulator-only runs so temporary workspace copies do not fail on local macOS metadata during codesign. This does not change the project's actual signing configuration in Xcode.

## Deep Cleanup
Use `scripts/deep-clean.sh` only when local disk usage becomes excessive or build state is clearly corrupted.

The deep cleanup removes heavier AuraShift-local artifacts:
- everything under `.aura-local`
- project-local `build/` and `.build/`
- `xcuserdata` inside `AuraShift.xcodeproj`
- AuraShift-specific Xcode DerivedData folders under `~/Library/Developer/Xcode/DerivedData`

## When To Use Each
- Use lightweight cleanup for normal daily build/test cycles.
- Use deep cleanup when repeated build issues persist or disk usage from AuraShift artifacts grows too large.
- Use `AURASHIFT_SIMULATOR_DESTINATION` if you need to force `scripts/test-local.sh` onto a specific simulator destination.
- Use `AURASHIFT_SIMULATOR_NAME` or `AURASHIFT_SIMULATOR_TYPE` only if the default dedicated AuraShift simulator needs to be overridden.
- Use `AURASHIFT_RUNNER_DIR` only if the temporary runner workspace parent needs to be redirected from `${TMPDIR}/aurashift-runner-workspaces`.

## Must Never Be Deleted Automatically
- source files
- `.env` files or configuration files
- signing files, certificates, or provisioning profiles
- all global DerivedData
- simulator runtimes
- dependency folders unless a future task explicitly proves that cleanup is safe and necessary
