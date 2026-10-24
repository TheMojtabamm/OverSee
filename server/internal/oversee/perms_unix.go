//go:build unix

package oversee

import (
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"syscall"
)

// inheritOwner gives f the owner and group of dir. `oversee` run as root creates files that
// the gate service (user "oversee", group "oversee") must still be able to read; without this
// they were root:root and the gate died with "permission denied".
func inheritOwner(f *os.File, dir string) {
	if os.Geteuid() != 0 {
		return
	}
	fi, err := os.Stat(dir)
	if err != nil {
		return
	}
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		_ = f.Chown(int(st.Uid), int(st.Gid))
	}
}

// FixPerms repairs ownership of the files in dir so the gate service can read them: group
// "oversee" (or dir's own group), group-readable and -writable. It is what
// `oversee fixperms` runs, and the service runs it before every start. It does nothing unless root.
func FixPerms(dir string) (fixed int, err error) {
	if os.Geteuid() != 0 {
		return 0, nil
	}
	gid := -1
	if g, e := user.LookupGroup("oversee"); e == nil {
		if n, e := strconv.Atoi(g.Gid); e == nil {
			gid = n
		}
	}
	if gid < 0 {
		return 0, nil // no service group on this machine: nothing to repair
	}
	_ = os.Chown(dir, 0, gid)
	_ = os.Chmod(dir, 0o770)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, err
	}
	for _, e := range entries {
		if !e.Type().IsRegular() {
			continue
		}
		p := filepath.Join(dir, e.Name())
		if os.Chown(p, 0, gid) == nil && os.Chmod(p, 0o660) == nil {
			fixed++
		}
	}
	return fixed, nil
}
