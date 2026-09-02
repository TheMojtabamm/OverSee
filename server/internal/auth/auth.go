// Package auth handles install-token issuance/verification for the app and
// will later hold the owner JWT helpers. It issues opaque random install
// tokens; only a sha256 hash of a token is ever stored, so a leaked DB does not
// expose usable tokens.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
)

// NewInstallToken returns a fresh opaque token (base64url) and its sha256 hex
// hash. Store the hash; hand the raw token to the app once.
func NewInstallToken() (token, hash string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", err
	}
	token = base64.RawURLEncoding.EncodeToString(b)
	return token, HashToken(token), nil
}

// HashToken returns the hex sha256 of a raw token, the form we persist.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
