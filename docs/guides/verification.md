# Verification

Install the pinned Rokit tools and documentation dependencies, then run the guarded gates from the
repository root:

```powershell
rokit install
npm install
.\scripts\verify\stylua.ps1
.\scripts\verify\selene.ps1
.\scripts\verify\analyze.ps1
.\scripts\verify\tests.ps1
.\scripts\verify\benchmark.ps1
npm run docs:build
```

`tests.ps1` runs deterministic Lune behavioral specs for the raw core and optional driver.
`analyze.ps1` checks strict implementation and public-contract typing. StyLua is check-only, Selene
checks lint/parse errors, and the benchmark gate measures bounded reconciliation work plus a
deterministic shared-read/unchanged-deadline driver profile.

## Studio verification

The deterministic suite proves scheduling behavior with a fake provider. Before an operator
integrates a release, also verify the current Studio harness against Roblox execution:

- raw Playback can advance from manually supplied absolute samples without constructing a driver;
- an ordinary event-only driven Playback keeps one deadline and no phase binding;
- backward arrival at a Sample's excluded end emits no Sample there, retains shared phase
  observation, and samples the first position inside the interval;
- event-only duration-side/zero-side pending loop joins retain exact identity while stationary,
  use transient phase observation, and consume the join on the first actual outward movement;
- sampled Playbacks sharing one driver perform one provider read per ordinary phase notification
  and do not reschedule unchanged deadlines;
- large forward/backward and repeated loops preserve event, reverse, and loop ordering while the
  final Sample runs once;
- exact loop joins preserve the requested `timePosition` and `loopIndex`;
- event, reverse, Sample, setup, address, and loop callbacks receive the same context identity;
- initial skip suppresses historical Events while `onAddress` and active Samples materialize the
  target in order;
- pause/resume and speed changes stay anchored to the accepted coordinate;
- driven external mutations reconcile the current provider sample first;
- attachment gives the returned DrivenPlayback exclusive temporal-control ownership until detach;
- discontinuity `skip`, `reconstruct`, and `cancel` behave independently of Sequence content;
- a zero-duration non-looping Sequence completes synchronously without scheduling ownership;
- detach, cancellation, driver destruction, and provider destruction release tasks and bindings
  without destroying the borrowed provider.

Package publication, version changes, and consumer dependency operations are separate operator
actions and are not part of these verification commands.
