package lock

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"time"
)

// blobEnvelope is the JSON structure serialized into the locked blob. Only the
// public fields (for display) are readable without the key; the actual config
// sits inside Ciphertext.
type blobEnvelope struct {
	V          int    `json:"v"`          // format version
	BlobID     string `json:"blobId"`
	Protocol   string `json:"protocol"`
	Title      string `json:"title"`
	Host       string `json:"host,omitempty"`
	Ciphertext string `json:"c"`          // base64 AES-GCM (nonce+tag+data)
}

// BuildLockedBlob encrypts the raw config and returns the base64url locked blob
// string that the owner pastes into Telegram. The owner also receives the
// metadata so the app can display it without decrypting.
//
// clientKeyMaterial is the key material embedded at build-time in the app; it
// must match what the client uses. Epoch is derived from the current day so keys
// rotate daily.
func (m *MasterKey) BuildLockedBlob(clientKeyMaterial, blobID, rawConfig string, meta ConfigMeta, epoch int64) (string, error) {
	key := m.FinalKeyMaterial(clientKeyMaterial, blobID, epoch)

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	sealed := gcm.Seal(nonce, nonce, []byte(rawConfig), nil)

	env := blobEnvelope{
		V:          2,
		BlobID:     blobID,
		Protocol:   meta.Protocol,
		Title:      meta.Title,
		Host:       meta.Host,
		Ciphertext: base64.RawURLEncoding.EncodeToString(sealed),
	}
	raw, err := json.Marshal(env)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

// DecodeBlob verifies the blob envelope (reads public fields) without needing a
// key — used to sanity-check a blob and to recover its public metadata.
func DecodeBlob(locked string) (*blobEnvelope, error) {
	raw, err := base64.RawURLEncoding.DecodeString(locked)
	if err != nil {
		return nil, err
	}
	var env blobEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return nil, err
	}
	if env.BlobID == "" || env.Ciphertext == "" {
		return nil, errors.New("invalid blob envelope")
	}
	return &env, nil
}

// EpochFor returns the daily epoch for a time.
func EpochFor(t time.Time) int64 {
	return t.UTC().Unix() / 86400
}

// NowEpoch returns the current daily epoch.
func NowEpoch() int64 {
	return EpochFor(time.Now())
}
