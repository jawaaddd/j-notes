package auth

import (
	"math"
	"sync"
	"time"
)

// limiter slows down password guessing for the whole server. The first few
// failures are free; after that each failure doubles the wait, up to maxWait.
type limiter struct {
	mu       sync.Mutex
	failures int
	until    time.Time
}

const (
	freeFailures = 5
	maxWait      = 5 * time.Minute
)

// wait reports how long the caller must wait before trying again (0 = now).
func (l *limiter) wait(now time.Time) time.Duration {
	l.mu.Lock()
	defer l.mu.Unlock()
	if now.Before(l.until) {
		return l.until.Sub(now)
	}
	return 0
}

func (l *limiter) fail(now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.failures++
	if l.failures < freeFailures {
		return
	}
	d := time.Duration(math.Pow(2, float64(l.failures-freeFailures))) * time.Second
	if d > maxWait || d <= 0 {
		d = maxWait
	}
	l.until = now.Add(d)
}

func (l *limiter) reset() {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.failures = 0
	l.until = time.Time{}
}
