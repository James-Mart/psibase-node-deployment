package strip_authelia_session

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestStripAutheliaSessionOnly(t *testing.T) {
	tests := []struct {
		name       string
		cookieName string
		setCookies []string
		wantCookie string
		wantAbsent bool
	}{
		{
			name:       "drops session and keeps the rest",
			cookieName: "authelia_session",
			setCookies: []string{"authelia_session=secret; theme=dark"},
			wantCookie: "theme=dark",
		},
		{
			name:       "session in the middle",
			cookieName: "authelia_session",
			setCookies: []string{"a=1; authelia_session=secret; b=2"},
			wantCookie: "a=1; b=2",
		},
		{
			name:       "only the session cookie removes the header",
			cookieName: "authelia_session",
			setCookies: []string{"authelia_session=secret"},
			wantAbsent: true,
		},
		{
			name:       "unrelated cookies pass through",
			cookieName: "authelia_session",
			setCookies: []string{"theme=dark; lang=en"},
			wantCookie: "theme=dark; lang=en",
		},
		{
			name:       "similar names are kept",
			cookieName: "authelia_session",
			setCookies: []string{"authelia_session_extra=1; not_authelia_session=2; authelia_session=secret"},
			wantCookie: "authelia_session_extra=1; not_authelia_session=2",
		},
		{
			name:       "empty config still drops the default name",
			setCookies: []string{"authelia_session=secret; theme=dark"},
			wantCookie: "theme=dark",
		},
		{
			name:       "multiple Cookie headers",
			cookieName: "authelia_session",
			setCookies: []string{"authelia_session=secret", "theme=dark"},
			wantCookie: "theme=dark",
		},
		{
			name:       "value may contain equals",
			cookieName: "authelia_session",
			setCookies: []string{"authelia_session=abc=def; keep=1"},
			wantCookie: "keep=1",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var got string
			var present bool
			next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				values := r.Header.Values("Cookie")
				present = len(values) > 0
				got = r.Header.Get("Cookie")
				if got == "" && present {
					t.Errorf("Cookie header is present but empty")
				}
			})

			handler, err := New(context.Background(), next, &Config{CookieName: tt.cookieName}, "test")
			if err != nil {
				t.Fatalf("New: %v", err)
			}

			req := httptest.NewRequest(http.MethodGet, "https://example.test/", nil)
			req.Header.Del("Cookie")
			for _, raw := range tt.setCookies {
				req.Header.Add("Cookie", raw)
			}
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, req)

			if tt.wantAbsent {
				if present {
					t.Fatalf("Cookie header = %q, want it absent", got)
				}
				return
			}
			if !present || got != tt.wantCookie {
				t.Fatalf("Cookie header = %q (present=%v), want %q", got, present, tt.wantCookie)
			}
		})
	}
}
