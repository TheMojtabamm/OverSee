package api

import (
	"github.com/google/uuid"
)

// newUUID returns a random v4 UUID string. Used for install ids and other
// generated identifiers the client does not supply.
func newUUID() string {
	return uuid.NewString()
}
