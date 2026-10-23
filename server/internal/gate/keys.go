package gate

import (
	"bufio"
	"os"
	"strings"
	"sync/atomic"
	"time"
)

// ParseKeys reads one app key per line (`#` comments allowed). The first key is the
// current one; later keys are previous releases still accepted during rollover.
func ParseKeys(sc *bufio.Scanner) ([][]byte, error) {
	var out [][]byte
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if i := strings.Index(line, "#"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line != "" {
			out = append(out, []byte(line))
		}
	}
	return out, sc.Err()
}

// KeyFile is a file-backed list of app keys, reloaded when it changes so rotating
// the key needs no restart.
type KeyFile struct {
	path    string
	extra   [][]byte // e.g. from the GATE_KEYS environment variable
	cur     atomic.Pointer[[][]byte]
	modTime time.Time
}

func LoadKeyFile(path string, extra [][]byte) (*KeyFile, error) {
	k := &KeyFile{path: path, extra: extra}
	if err := k.reload(); err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	if k.cur.Load() == nil {
		k.store(nil)
	}
	return k, nil
}

func (k *KeyFile) store(fileKeys [][]byte) {
	all := append(append([][]byte{}, fileKeys...), k.extra...)
	k.cur.Store(&all)
}

func (k *KeyFile) reload() error {
	f, err := os.Open(k.path)
	if err != nil {
		return err
	}
	defer f.Close()
	st, _ := f.Stat()
	keys, err := ParseKeys(bufio.NewScanner(f))
	if err != nil {
		return err
	}
	k.store(keys)
	if st != nil {
		k.modTime = st.ModTime()
	}
	return nil
}

func (k *KeyFile) Watch(every time.Duration, onErr func(error)) {
	go func() {
		for range time.Tick(every) {
			st, err := os.Stat(k.path)
			if err != nil || st.ModTime().Equal(k.modTime) {
				continue
			}
			if err := k.reload(); err != nil {
				onErr(err)
				k.modTime = st.ModTime()
			}
		}
	}()
}

func (k *KeyFile) Get() [][]byte { return *k.cur.Load() }
