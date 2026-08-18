---
layout: home

hero:
  name: Pulse
  text: Absolute-time sequence evaluation
  tagline: Reusable event traversal and sampled state, driven by explicit host time.
  actions:
    - theme: brand
      text: Get started
      link: /guides/getting-started
    - theme: alt
      text: API reference
      link: /api/

features:
  - title: Raw and externally evaluable
    details: A Playback advances only when the host supplies a finite absolute TimeSample.
  - title: Absolute sampled state
    details: Active samplers receive the final position and effective rate once, without a synthetic dt.
  - title: Optional scheduling
    details: ClockDriver adds shared phase fan-out and next-boundary deadlines without entering the core contract.
---

Pulse is a standalone, strictly typed Luau package. It compiles an immutable
[`Sequence`](./api/components/sequence.md), creates a raw
[`Playback`](./api/components/playback.md), and optionally attaches it to a scheduling-capable
provider through [`ClockDriver`](./api/managers/clockDriver.md).

Pulse contains no VFX, character, networking, prediction, or service policy. A consumer supplies
domain context and side effects, owns whether motion is traversal or an address operation, and
chooses how an optional driver responds to a provider discontinuity.
