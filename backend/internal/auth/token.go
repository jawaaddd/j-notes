package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"strings"
)

const tokenPrefix = "nts_"

// NewToken returns a fresh token string and the hash to store for it.
// Tokens carry 256 bits of randomness, so a plain SHA-256 is enough to store
// them safely; slow hashing is only needed for low-entropy passwords.
func NewToken() (string, [32]byte, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", [32]byte{}, err
	}
	tok := tokenPrefix + base64.RawURLEncoding.EncodeToString(b)
	return tok, HashToken(tok), nil
}

func HashToken(tok string) [32]byte { return sha256.Sum256([]byte(tok)) }

// NewSetupCode returns a short one-time code for first-run setup, using
// characters that are hard to misread (no 0/O, 1/I/L).
func NewSetupCode() (string, error) {
	const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	var sb strings.Builder
	for i, v := range b {
		if i == 4 {
			sb.WriteByte('-')
		}
		sb.WriteByte(alphabet[int(v)%len(alphabet)])
	}
	return sb.String(), nil
}
