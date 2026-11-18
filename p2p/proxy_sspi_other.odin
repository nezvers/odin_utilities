#+build !windows
#+build !js
package p2p

// Only Windows has SSPI (the login of the user for a proxy that asks for NTLM). Elsewhere NTLM works with a user name and password in the
// proxy URL (proxy_ntlm.odin).
SSPI_AVAILABLE :: false

SspiState :: struct {
    unused: u8,
}

@(private)
SspiOpen :: proc(package_name: string, host: string) -> (state: ^SspiState, ok: bool) {
    return nil, false
}

@(private)
SspiStep :: proc(state: ^SspiState, input: []byte) -> (output: []byte, done: bool, ok: bool) {
    return nil, false, false
}

@(private)
SspiClose :: proc(state: ^SspiState) {
}
