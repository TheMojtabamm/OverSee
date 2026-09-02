// Package auth also provides owner (dashboard) JWT access-token helpers.
package auth

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// OwnerClaims are the JWT claims carried in an owner's dashboard token.
type OwnerClaims struct {
	OwnerID int64 `json:"oid"` // owner id, not email, so lookups stay cheap
	jwt.RegisteredClaims
}

// IssueOwnerToken mints a signed JWT valid for ttl for the given owner id.
func IssueOwnerToken(secret string, ownerID int64, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := OwnerClaims{
		OwnerID: ownerID,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return tok.SignedString([]byte(secret))
}

// ParseOwnerToken validates a signed JWT and returns the owning owner id.
func ParseOwnerToken(secret, tokenStr string) (int64, error) {
	claims := &OwnerClaims{}
	_, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(secret), nil
	})
	if err != nil {
		return 0, err
	}
	return claims.OwnerID, nil
}
