// shrimp-tsnet — Shrimp'in uygulamaya-özel userspace Tailscale node'u.
// Kendi Tailscale kimliğiyle tailnet'e katılır (resmi Tailscale app GEREKMEZ),
// yerel 127.0.0.1:<port>'u PC agent'ına (tailnet hedefi) TCP-forward eder.
// Shrimp bu yerel porta bağlanır. Login gerekiyorsa authURL'i stdout'a JSON basar.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"time"

	"tailscale.com/tsnet"
)

func emit(m map[string]any) { b, _ := json.Marshal(m); fmt.Println(string(b)); os.Stdout.Sync() }

func main() {
	target := flag.String("target", "", "tailnet hedefi adres:port (PC agent, ör. 100.x:8787)")
	listen := flag.String("listen", "127.0.0.1:0", "yerel dinleme adresi")
	dir := flag.String("dir", "", "tsnet state dizini (node kimliği burada saklanır)")
	hostname := flag.String("hostname", "shrimp-mac", "tsnet node adı")
	flag.Parse()
	if *target == "" {
		emit(map[string]any{"state": "error", "error": "target gerekli"})
		os.Exit(1)
	}

	s := &tsnet.Server{
		Hostname: *hostname,
		Dir:      *dir,
		AuthKey:  os.Getenv("SHRIMP_TS_AUTHKEY"), // opsiyonel; yoksa interaktif login
		Logf:     func(string, ...any) {},        // sessiz
	}
	defer s.Close()

	ctx := context.Background()
	if err := s.Start(); err != nil {
		emit(map[string]any{"state": "error", "error": err.Error()})
		os.Exit(1)
	}
	lc, err := s.LocalClient()
	if err != nil {
		emit(map[string]any{"state": "error", "error": err.Error()})
		os.Exit(1)
	}

	// Running olana kadar bekle; login gerekiyorsa authURL'i bildir.
	lastURL := ""
	for {
		st, err := lc.Status(ctx)
		if err == nil && st != nil {
			if st.BackendState == "Running" {
				break
			}
			if st.AuthURL != "" && st.AuthURL != lastURL {
				lastURL = st.AuthURL
				emit(map[string]any{"state": "needsLogin", "authURL": st.AuthURL})
			}
		}
		time.Sleep(500 * time.Millisecond)
	}

	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		emit(map[string]any{"state": "error", "error": err.Error()})
		os.Exit(1)
	}
	emit(map[string]any{"state": "running", "listen": ln.Addr().String()})

	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go forward(s, c, *target)
	}
}

// Yerel bağlantıyı tailnet hedefine köprüle.
func forward(s *tsnet.Server, local net.Conn, target string) {
	defer local.Close()
	remote, err := s.Dial(context.Background(), "tcp", target)
	if err != nil {
		return
	}
	defer remote.Close()
	go func() { io.Copy(remote, local) }()
	io.Copy(local, remote)
}
