#+build !windows
#+build !js
package native

import "core:os"

// Other systems do not hand the pipes of the browser to a child that is started with nothing to inherit
@(private)
startDetached :: proc(command: []string) -> bool {
	_, error := os.process_start({command = command})
	return error == nil
}
