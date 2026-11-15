# lanes

SPMD fan out for non realtime work (the lane model of the RAD Debugger): `lanes.Run(count, Work, user)` runs the same `Work` on `count` lanes (the caller is lane 0), and a lane divides
the work with `LaneRange(lane, n)`, waits for the others with `LaneSync`, and shares a small value with `LaneBroadcast(lane, &value, source)`. No task queue, no allocation while it runs.
Not for the audio thread: odin_plug's `graph/pool.odin` is the realtime pool. Not for the web (`#+build !js`). Test: `odin test lanes -strict-style -vet`. No demos: nothing is drawn.
