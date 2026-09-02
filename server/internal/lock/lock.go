// Package lock implements the server side of the v2 locked-config system.
//
// The locked config is an opaque blob whose opening requires server-side
// participation. This system ensures that configs are server-gated and
// cannot be used offline indefinitely.
//
// The derivation below must be re-implemented identically in the Flutter client
// (lib/services/locked_config_codec.dart) in phase 6 of the plan.
package lock

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
)

// MasterKey holds the server-side secret used to derive per-blob components.
type MasterKey struct {
	// key is the LOCK_SERVER_KEY env value.
	key []byte
}

// NewMasterKey wraps the server secret; key must be non-empty.
func NewMasterKey(key string) *MasterKey {
	return &MasterKey{key: []byte(key)}
}

// ComponentFor derives the server component for a (blobId, epoch) pair.
func (m *MasterKey) ComponentFor(blobID string, epoch int64) string {
	mac := hmac.New(sha256.New, m.key)
	mac.Write([]byte("oversea|blob|"))
	mac.Write([]byte(strconv.FormatInt(epoch, 10)))
	mac.Write([]byte("|"))
	mac.Write([]byte(blobID))
	return hex.EncodeToString(mac.Sum(nil))
}

// FinalKeyMaterial computes the full key material used for AES-256-GCM.
func (m *MasterKey) FinalKeyMaterial(clientKeyMaterial, blobID string, epoch int64) []byte {
	component := m.ComponentFor(blobID, epoch)
	mac := hmac.New(sha256.New, []byte(clientKeyMaterial))
	mac.Write([]byte("oversea-lock|v2|"))
	mac.Write([]byte(strconv.FormatInt(epoch, 10)))
	mac.Write([]byte("|"))
	mac.Write([]byte(blobID))
	mac.Write([]byte("|"))
	mac.Write([]byte(component))
	return mac.Sum(nil)
}
