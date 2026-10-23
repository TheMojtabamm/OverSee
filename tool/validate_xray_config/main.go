// validate_xray_config loads each given JSON file with Xray-core's own config
// loader (the same code path the app's core uses) and reports whether it parses
// and builds. It does not start anything.
//
//	go run . config1.json config2.json
package main

import (
	"fmt"
	"os"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

func main() {
	failed := 0
	for _, p := range os.Args[1:] {
		f, err := os.Open(p)
		if err != nil {
			fmt.Printf("FAIL %s: %v\n", p, err)
			failed++
			continue
		}
		cfg, err := serial.LoadJSONConfig(f)
		f.Close()
		if err != nil {
			fmt.Printf("FAIL %s: %v\n", p, err)
			failed++
			continue
		}
		// core.New instantiates features (without Start), catching semantic errors.
		if _, err := core.New(cfg); err != nil {
			fmt.Printf("FAIL %s (core.New): %v\n", p, err)
			failed++
			continue
		}
		fmt.Printf("ok   %s\n", p)
	}
	if failed > 0 {
		os.Exit(1)
	}
}
