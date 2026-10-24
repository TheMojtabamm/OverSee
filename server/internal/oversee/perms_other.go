//go:build !unix

package oversee

import "os"

func inheritOwner(*os.File, string) {}

// FixPerms is a no-op where there is no service user.
func FixPerms(string) (int, error) { return 0, nil }
