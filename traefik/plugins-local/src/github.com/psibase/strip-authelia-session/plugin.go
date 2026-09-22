// Package strip_authelia_session removes one named cookie from the request
// Cookie header. Traefik's headers middleware can only replace the whole
// header, so this plugin lives in-repo and drops authelia_session alone.
package strip_authelia_session

import (
	"context"
	"net/http"
	"strings"
)

const defaultCookieName = "authelia_session"

// Config is the middleware configuration decoded from the Traefik dynamic config.
type Config struct {
	CookieName string `json:"cookieName,omitempty"`
}

// CreateConfig returns the default configuration.
func CreateConfig() *Config {
	return &Config{
		CookieName: defaultCookieName,
	}
}

type strip struct {
	next       http.Handler
	cookieName string
}

// New builds the middleware. An empty cookie name falls back to authelia_session.
func New(ctx context.Context, next http.Handler, config *Config, name string) (http.Handler, error) {
	_ = ctx
	_ = name

	cookieName := defaultCookieName
	if config != nil {
		if configured := strings.TrimSpace(config.CookieName); configured != "" {
			cookieName = configured
		}
	}

	return &strip{
		next:       next,
		cookieName: cookieName,
	}, nil
}

func (s *strip) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	stripNamedCookie(req.Header, s.cookieName)
	s.next.ServeHTTP(rw, req)
}

// stripNamedCookie drops every cookie whose name equals name and forwards the rest.
// When nothing remains, the Cookie header is removed rather than set to empty.
func stripNamedCookie(header http.Header, name string) {
	rawValues := header["Cookie"]
	if len(rawValues) == 0 {
		return
	}

	kept := make([]string, 0)
	for _, raw := range rawValues {
		for _, part := range strings.Split(raw, ";") {
			token := strings.TrimSpace(part)
			if token == "" {
				continue
			}
			cookieName := token
			if eq := strings.IndexByte(token, '='); eq >= 0 {
				cookieName = strings.TrimSpace(token[:eq])
			}
			if cookieName == name {
				continue
			}
			kept = append(kept, token)
		}
	}

	header.Del("Cookie")
	if len(kept) > 0 {
		header.Set("Cookie", strings.Join(kept, "; "))
	}
}
