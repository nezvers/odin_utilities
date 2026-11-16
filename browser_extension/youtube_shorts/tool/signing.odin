package main

// Credentials for signing the Firefox build with Mozilla (`--release` for firefox). THE VALUES BELOW ARE TEMPLATES: replace them with your own.
// Get them (free) at https://addons.mozilla.org/developers/addon/api/key/ : "JWT issuer" is the key, "JWT secret" is the secret.
//
// This file is in git ignore: the template was committed once (git add -f) and git is told to leave later edits of it alone
// (`git update-index --skip-worktree`), so your real secret does not get committed. Never paste the secret anywhere else.
// WEB_EXT_API_KEY / WEB_EXT_API_SECRET in the environment still work when the values here are left as the templates.

MOZILLA_API_KEY :: "user:00000000:000"                  // template: JWT issuer
MOZILLA_API_SECRET :: "0000000000000000000000000000000000000000000000000000000000000000" // template: JWT secret

// The credentials to use, empty when this file still holds the templates
SigningCredentials :: proc() -> (key, secret: string) {
	if MOZILLA_API_KEY == "user:00000000:000" || len(MOZILLA_API_KEY) == 0 || len(MOZILLA_API_SECRET) == 0 {
		return "", ""
	}
	return MOZILLA_API_KEY, MOZILLA_API_SECRET
}
