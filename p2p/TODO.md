# p2p TODO

Tick an item when it is done and verified (tests pass, committed).

## Low priority
- [ ] Test the Kerberos login (the Negotiate scheme of an HTTP proxy, `proxy_sspi_windows.odin`) against a real Kerberos realm. Until then only the NTLM fallback was exercised (the computer
      the tests run on is not in a domain, so SSPI picks NTLM). A free way, scripted:
  - A MIT Kerberos KDC in a container (realm such as `TEST.LOCAL`, a user, the service `HTTP/proxy.test.local`) and Squid with `negotiate_kerberos_auth` and the keytab in a second one.
  - `proxy.test.local` in the hosts file (Kerberos needs the real name of the proxy, not an address), and a registry key under `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Domains\<REALM>`
    with the KDC address so Windows finds the realm (set by the script, removed afterwards; needs administrator rights once; Docker or WSL must be running).
  - New: Negotiate with an explicit user and password (`REALM\user:password` through SSPI with an identity), because a computer that is not in the realm has no ticket for the signed in user.
    It is useful on its own for logging in as another account.
  - A tool (`p2p/tool/...`) that sets it up, connects through the proxy by name, prints which package SSPI chose (Kerberos or NTLM) and checks the Squid log for a Kerberos authenticated user.
  - Other route, no new code: a Windows evaluation VM joined to a Samba AD domain, tested as a signed in domain user (heavy: an ISO, Hyper-V, an evaluation licence that expires).
- [ ] Kerberos on Linux and macOS (GSSAPI, a ticket from `kinit` or a keytab, the same service name rule). Nothing of it exists now: there the message asks for `DOMAIN\user:password` (NTLM).
