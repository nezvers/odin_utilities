# scratch

Thread local scratch memory with the conflict rule of the RAD Debugger. Two arenas per thread (`core:mem/virtual`: they reserve 64 MB of address space and commit as used),
`ScratchBegin(conflicts..)` takes the one that is not a conflict, `ScratchEnd` releases everything allocated since. A function that writes its result into an arena names it as a conflict
and its temporaries go into the other one, so they die at `ScratchEnd` without taking the result with them. No allocator passed down, no frees one by one.

```odin
scratch := scratch.ScratchBegin(result_arena)
defer scratch.ScratchEnd(scratch)
words := make([dynamic]string, scratch.ScratchAllocator(scratch))
```
For tools, loaders and tests, not for an audio thread. `ScratchRelease()` before a thread ends. `-define:SCRATCH_RESERVE=n` sets the reserve (bytes).
Not for the web (`#+build !js`). Test: `odin test scratch -strict-style -vet`. No demos: nothing is drawn.
