package gate

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Stats counts, per lock and per UTC day, how many connections were admitted and
// from how many distinct IPs, plus why connections were refused. The distinct-IP
// count is the leak signal: a lock meant for a handful of people that suddenly
// shows hundreds of IPs has been shared. IPs are kept only as salted 64-bit hashes
// in memory and are never written to disk.
type Stats struct {
	mu      sync.Mutex
	salt    [16]byte
	day     int64
	locks   map[string]*lockStat
	rejects map[string]int
	maxIPs  int
}

type lockStat struct {
	accepted int
	ips      map[uint64]struct{}
	last     time.Time
}

func NewStats() *Stats {
	s := &Stats{locks: map[string]*lockStat{}, rejects: map[string]int{}, maxIPs: 20000}
	rand.Read(s.salt[:])
	return s
}

func (s *Stats) roll(now time.Time) {
	d := now.UTC().Unix() / bucketSeconds
	if d != s.day {
		s.day, s.locks, s.rejects = d, map[string]*lockStat{}, map[string]int{}
	}
}

func (s *Stats) hashIP(ip string) uint64 {
	h := sha256.Sum256(append(s.salt[:], ip...))
	return binary.BigEndian.Uint64(h[:8])
}

func (s *Stats) accept(id, ip string, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.roll(now)
	ls := s.locks[id]
	if ls == nil {
		ls = &lockStat{ips: map[uint64]struct{}{}}
		s.locks[id] = ls
	}
	ls.accepted++
	ls.last = now
	if len(ls.ips) < s.maxIPs {
		ls.ips[s.hashIP(ip)] = struct{}{}
	}
}

func (s *Stats) reject(reason string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.roll(time.Now())
	s.rejects[reason]++
}

// LockSnapshot / Snapshot are the JSON the TUI reads.
type LockSnapshot struct {
	CodeID      string    `json:"codeId"`
	Accepted    int       `json:"accepted"`
	DistinctIPs int       `json:"distinctIps"`
	Last        time.Time `json:"last"`
}

type Snapshot struct {
	Day     string         `json:"day"`
	Updated time.Time      `json:"updated"`
	Locks   []LockSnapshot `json:"locks"`
	Rejects map[string]int `json:"rejects"`
}

func (s *Stats) Snapshot(now time.Time) Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.roll(now)
	out := Snapshot{Day: now.UTC().Format("2006-01-02"), Updated: now.UTC(), Rejects: map[string]int{}}
	for k, v := range s.rejects {
		out.Rejects[k] = v
	}
	for id, ls := range s.locks {
		out.Locks = append(out.Locks, LockSnapshot{CodeID: id, Accepted: ls.accepted, DistinctIPs: len(ls.ips), Last: ls.last.UTC()})
	}
	sort.Slice(out.Locks, func(i, j int) bool { return out.Locks[i].CodeID < out.Locks[j].CodeID })
	return out
}

// WriteLoop writes the snapshot to path (atomically) every interval.
func (s *Stats) WriteLoop(path string, every time.Duration) {
	go func() {
		for range time.Tick(every) {
			_ = s.WriteOnce(path)
		}
	}()
}

func (s *Stats) WriteOnce(path string) error {
	b, err := json.Marshal(s.Snapshot(time.Now()))
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".stats-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		return err
	}
	tmp.Chmod(0o644)
	tmp.Close()
	return os.Rename(tmp.Name(), path)
}

// ReadSnapshot loads what the running gate last wrote (zero value if none).
func ReadSnapshot(path string) (Snapshot, error) {
	var sn Snapshot
	b, err := os.ReadFile(path)
	if err != nil {
		return sn, err
	}
	err = json.Unmarshal(b, &sn)
	return sn, err
}

// AcceptForTest records an admitted connection (exported for tests in other packages).
func (s *Stats) AcceptForTest(id, ip string, now time.Time) { s.accept(id, ip, now) }
