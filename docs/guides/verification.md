# Verification

Install the pinned Rokit tools and documentation dependencies, then run the guarded gates from the
repository root:

```powershell
rokit install
npm install
.\scripts\verify\tests.ps1
.\scripts\verify\analyze.ps1
.\scripts\verify\stylua.ps1
.\scripts\verify\selene.ps1
npm run docs:build
```

`tests.ps1` runs the deterministic Lune behavioral suite. `analyze.ps1` checks strict public and
implementation typing. StyLua is check-only, and Selene checks lint and parse errors.

## Studio verification

Lune proves the borrowed-clock contract with deterministic fakes. Before integrating a release,
also verify the current Studio harness against Roblox execution:

- a one-step event remains scheduled without a phase binding;
- an updating trail receives phase updates only within its active interval;
- multiple updating playbacks sharing one adapter use one phase binding;
- repeated forward and backward loops preserve event and loop ordering;
- exact-boundary direction changes do not double-run or skip callbacks;
- repeated structured loop seeks keep the requested `timePosition` and `loopIndex`;
- per-play context identity reaches event, reverse, update, setup, address, and loop callbacks;
- late initial skip suppresses historical one-shots while `onAddress` materializes the target state;
- a zero-duration non-looping Sequence completes synchronously without scheduler ownership;
- pause, resume, speed changes, cancellation, and adapter destruction release ownership.

Package publication and consumer Pesde operations are separate operator actions and are not part of
these verification commands.
