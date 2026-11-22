# wait_for

Waiting in real time for something that happens on another clock (a server that starts, a peer that answers, a thread that decodes), with a limit that is a **time** and a way to give a slower device more of it.

A test that polls 800 times and gives up has an allowance of 800 turns: as many real seconds as the turns take on the computer that wrote it. A slower device needs more time for the same thing, and the other party (a server process, a network peer) does not slow down with our turns. So the allowance is a time, and one number says how much slower a device is: the environment variable `ODIN_SLOW` (`ODIN_SLOW=3` on a device that needs three times the time, 1 when it is not set, at most 100).

```odin
deadline: wait_for.Deadline = wait_for.DeadlineStart(20)             // 20 seconds on a quiet computer, 60 with ODIN_SLOW=3
for !wait_for.DeadlineExpired(&deadline) {
    UpdateBoth()
    if connected() { break }
    time.sleep(time.Millisecond)
}
```
or `wait_for.Until(20, poll)`, where `poll(user)` does a turn of the work and says whether it happened (it runs at least once, also with no time left).

| | |
|---|---|
| `Scale()` | the scale of this run (`ODIN_SLOW`), read once; `ScaleFrom(text)` is the pure part: a number of 1 or more, else 1, at most 100 |
| `DeadlineStart(seconds)` | a deadline `seconds * Scale()` of real time from now; `DeadlineExpired`, `DeadlineElapsed`, `DeadlineLimit` |
| `Until(seconds, poll, user, pause)` | the loop above |

## Used by
- `demo_kit`: `kit.WaitUntil(check, message, seconds)` waits in real time and multiplies by `TimeScale`, which the test programs take from `Scale()`.
- The timeouts of `spacetimedb` (a request, the handshake of a websocket, the start of a server, a wait for a message), `oidc` (a request) and the stages of the arena session are multiplied by their `TimeScale`, set from `Scale()` when the program starts: run the arena with `ODIN_SLOW=3` on a slow computer.
- The tests of the libraries that talk to servers, sockets or threads (`spacetimedb`, `ai_messaging`, `oidc`, `scene`) poll with deadlines, not with counts of turns.

Tests: `odin test wait_for` (also `ODIN_SLOW=3 odin test wait_for`).
