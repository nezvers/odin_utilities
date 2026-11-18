#+build windows
package p2p

foreign import p2p_secur32 "system:secur32.lib"

// Windows login for a proxy that asks for "Negotiate" (Kerberos, falling back to NTLM) or "NTLM": SSPI does it with the credentials of the
// user who is logged in, so nothing is written in the proxy URL. The proxy is addressed by the service name HTTP/<host> (Kerberos needs the real
// name of the proxy, an address can only do NTLM).

@(private = "file")
SecHandle :: struct {
    lower: uintptr,
    upper: uintptr,
}

@(private = "file")
SecBuffer :: struct {
    size: u32,
    type: u32,
    data: rawptr,
}

@(private = "file")
SecBufferDesc :: struct {
    version: u32,
    count: u32,
    buffers: ^SecBuffer,
}

SEC_E_OK :: i32(0)
SEC_I_CONTINUE_NEEDED :: i32(0x00090312)
SECBUFFER_TOKEN :: 2
SECPKG_CRED_INBOUND :: 1
SECPKG_CRED_OUTBOUND :: 2
ISC_REQ_CONNECTION :: 0x800
ASC_REQ_CONNECTION :: 0x800
SECURITY_NATIVE_DREP :: 0x10
SSPI_TOKEN_MAX :: 65536

@(default_calling_convention = "system")
foreign p2p_secur32 {
    AcquireCredentialsHandleW :: proc(principal: cstring16, package_name: cstring16, use: u32, logon_id: rawptr, auth_data: rawptr, get_key: rawptr, get_key_argument: rawptr, credential: ^SecHandle, expiry: ^i64) -> i32 ---
    InitializeSecurityContextW :: proc(credential: ^SecHandle, context_handle: ^SecHandle, target: cstring16, flags: u32, reserved1: u32, data_representation: u32, input: ^SecBufferDesc, reserved2: u32, new_context: ^SecHandle, output: ^SecBufferDesc, attributes: ^u32, expiry: ^i64) -> i32 ---
    AcceptSecurityContext :: proc(credential: ^SecHandle, context_handle: ^SecHandle, input: ^SecBufferDesc, flags: u32, data_representation: u32, new_context: ^SecHandle, output: ^SecBufferDesc, attributes: ^u32, expiry: ^i64) -> i32 ---
    DeleteSecurityContext :: proc(context_handle: ^SecHandle) -> i32 ---
    FreeCredentialsHandle :: proc(credential: ^SecHandle) -> i32 ---
}

SspiState :: struct {
    credential: SecHandle,
    context_handle: SecHandle,
    have_context: bool,
    target: [260]u16,                       // "HTTP/host", UTF-16, zero ended
}

// SSPI is there on Windows.
SSPI_AVAILABLE :: true

// A client of the package ("Negotiate" or "NTLM") for the proxy `host`, using the login of the current user.
@(private)
SspiOpen :: proc(package_name: string, host: string) -> (state: ^SspiState, ok: bool) {
    state = new(SspiState)
    name: [32]u16
    for i in 0 ..< min(len(package_name), 31) {
        name[i] = u16(package_name[i])
    }
    expiry: i64
    if AcquireCredentialsHandleW(nil, cstring16(raw_data(name[:])), SECPKG_CRED_OUTBOUND, nil, nil, nil, nil, &state.credential, &expiry) != SEC_E_OK {
        free(state)
        return nil, false
    }
    target: string = "HTTP/"
    at: int
    for c in target {
        state.target[at] = u16(c)
        at += 1
    }
    for i in 0 ..< len(host) {
        if at >= len(state.target) - 1 {
            break
        }
        state.target[at] = u16(host[i])
        at += 1
    }
    return state, true
}

// The next token of the client for the token of the proxy (empty for the first). `done`: the login is complete on our side. The output is
// allocated; it may be empty when done.
@(private)
SspiStep :: proc(state: ^SspiState, input: []byte) -> (output: []byte, done: bool, ok: bool) {
    out_data: []byte = make([]byte, SSPI_TOKEN_MAX)
    out_buffer: SecBuffer = {size = SSPI_TOKEN_MAX, type = SECBUFFER_TOKEN, data = raw_data(out_data)}
    out_desc: SecBufferDesc = {version = 0, count = 1, buffers = &out_buffer}
    in_buffer: SecBuffer
    in_desc: SecBufferDesc
    in_pointer: ^SecBufferDesc
    if len(input) > 0 {
        in_buffer = {size = u32(len(input)), type = SECBUFFER_TOKEN, data = raw_data(input)}
        in_desc = {version = 0, count = 1, buffers = &in_buffer}
        in_pointer = &in_desc
    }
    attributes: u32
    expiry: i64
    status: i32 = InitializeSecurityContextW(
        &state.credential,
        &state.context_handle if state.have_context else nil,
        cstring16(raw_data(state.target[:])),
        ISC_REQ_CONNECTION,
        0,
        SECURITY_NATIVE_DREP,
        in_pointer,
        0,
        &state.context_handle,
        &out_desc,
        &attributes,
        &expiry,
    )
    if status != SEC_E_OK && status != SEC_I_CONTINUE_NEEDED {
        delete(out_data)
        return nil, false, false
    }
    state.have_context = true
    output = out_data[:out_buffer.size]
    return output, status == SEC_E_OK, true
}

@(private)
SspiClose :: proc(state: ^SspiState) {
    if state == nil {
        return
    }
    if state.have_context {
        DeleteSecurityContext(&state.context_handle)
    }
    FreeCredentialsHandle(&state.credential)
    free(state)
}

// The other side, for the tests: a server that checks the tokens of SspiStep against the accounts of this computer.
SspiServer :: struct {
    credential: SecHandle,
    context_handle: SecHandle,
    have_context: bool,
}

@(private)
SspiServerOpen :: proc(server: ^SspiServer) -> bool {
    name: [16]u16
    for c, i in ([?]u16{'N', 'e', 'g', 'o', 't', 'i', 'a', 't', 'e'}) {
        name[i] = c
    }
    expiry: i64
    return AcquireCredentialsHandleW(nil, cstring16(raw_data(name[:])), SECPKG_CRED_INBOUND, nil, nil, nil, nil, &server.credential, &expiry) == SEC_E_OK
}

// The server's token for the client's (allocated), and whether the login is complete (the client is who it says it is).
@(private)
SspiServerStep :: proc(server: ^SspiServer, input: []byte) -> (output: []byte, done: bool, ok: bool) {
    out_data: []byte = make([]byte, SSPI_TOKEN_MAX)
    out_buffer: SecBuffer = {size = SSPI_TOKEN_MAX, type = SECBUFFER_TOKEN, data = raw_data(out_data)}
    out_desc: SecBufferDesc = {version = 0, count = 1, buffers = &out_buffer}
    in_buffer: SecBuffer = {size = u32(len(input)), type = SECBUFFER_TOKEN, data = raw_data(input)}
    in_desc: SecBufferDesc = {version = 0, count = 1, buffers = &in_buffer}
    attributes: u32
    expiry: i64
    status: i32 = AcceptSecurityContext(
        &server.credential,
        &server.context_handle if server.have_context else nil,
        &in_desc,
        ASC_REQ_CONNECTION,
        SECURITY_NATIVE_DREP,
        &server.context_handle,
        &out_desc,
        &attributes,
        &expiry,
    )
    if status != SEC_E_OK && status != SEC_I_CONTINUE_NEEDED {
        delete(out_data)
        return nil, false, false
    }
    server.have_context = true
    return out_data[:out_buffer.size], status == SEC_E_OK, true
}

@(private)
SspiServerClose :: proc(server: ^SspiServer) {
    if server.have_context {
        DeleteSecurityContext(&server.context_handle)
    }
    FreeCredentialsHandle(&server.credential)
}
