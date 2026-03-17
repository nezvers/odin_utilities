#+private file
package demo

import ti ".."
Timer :: ti.Timer

@(private="package")
state_loop_timer: State = {
    init,
    finit,
    update,
    draw,
}

loop_timer: Timer = {
    wait = 120,
    mode = .loop,
    callbacks = {loop_timeout},
}

init :: proc() {}
finit :: proc() {}
update :: proc() {}
draw :: proc() {}

loop_timeout :: proc( timer: ^Timer) {
    
}