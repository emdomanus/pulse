---
layout: home

hero:
  name: Pulse
  text: Clock-driven sequence playback
  tagline: Reusable event and update timelines for Roblox, scheduled by a borrowed clock.
  actions:
    - theme: brand
      text: Get started
      link: /guides/getting-started
    - theme: alt
      text: API reference
      link: /api/

features:
  - title: Scheduled when idle
    details: Event-only playbacks keep one next-boundary task and do not create a frame callback.
  - title: Continuous when needed
    details: Updating playbacks lazily share one phase binding through their TemporalAdapter.
  - title: Explicit traversal
    details: Reverse callbacks, loop identity, discontinuity policy, playback speed, and cleanup are part of the sequence contract.
---

Pulse is a standalone, strictly typed Luau package. It compiles a reusable
[`Sequence`](./api/components/sequence.md), creates live
[`Playback`](./api/components/playback.md) instances, and connects them to a borrowed
scheduling-capable clock through a
[`TemporalAdapter`](./api/managers/temporalAdapter.md).

Pulse contains no VFX, character, networking, or service policy. A consumer supplies those meanings
through authored callbacks and owns any external state they create.
