package gate

import (
	"sync"
	"time"
)

// Limiter blocks an IP that keeps presenting bad tokens: after MaxFails failures
// within Window it is refused outright for BlockFor. This stops brute-forcing and
// means scanners cost the server almost nothing.
type Limiter struct {
	MaxFails int
	Window   time.Duration
	BlockFor time.Duration

	mu sync.Mutex
	m  map[string]*bucket
}

type bucket struct {
	fails        int
	windowStart  time.Time
	blockedUntil time.Time
}

func NewLimiter(maxFails int, window, blockFor time.Duration) *Limiter {
	return &Limiter{MaxFails: maxFails, Window: window, BlockFor: blockFor, m: map[string]*bucket{}}
}

func (l *Limiter) Blocked(ip string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.m[ip]
	return b != nil && now.Before(b.blockedUntil)
}

func (l *Limiter) Fail(ip string, now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.m) > 100000 { // bound memory under a flood of distinct IPs
		for k, b := range l.m {
			if now.After(b.blockedUntil) && now.Sub(b.windowStart) > l.Window {
				delete(l.m, k)
			}
		}
	}
	b := l.m[ip]
	if b == nil {
		b = &bucket{windowStart: now}
		l.m[ip] = b
	}
	if now.Sub(b.windowStart) > l.Window {
		b.fails, b.windowStart = 0, now
	}
	b.fails++
	if b.fails >= l.MaxFails {
		b.blockedUntil = now.Add(l.BlockFor)
		b.fails, b.windowStart = 0, now
	}
}
