package subtitle

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultOSBaseURL = "https://api.opensubtitles.com/api/v1"
	// osUserAgent identifies Argosy to OpenSubtitles; the API rejects requests
	// without a meaningful User-Agent.
	osUserAgent = "Argosy v0.1"
	// tokenTTL is how long a login JWT is trusted before re-login. Tokens are
	// valid ~24h; we refresh a little early.
	tokenTTL = 23 * time.Hour
)

// OpenSubtitles is a client for the opensubtitles.com REST API. Search needs
// only the API key; download is quota'd per user and requires a login JWT, so
// Configured() reports true only when username+password are also present.
type OpenSubtitles struct {
	apiKey     string
	username   string
	password   string
	http       *http.Client
	searchBase string // search base URL; overridable in tests

	mu       sync.Mutex
	token    string
	tokenExp time.Time
	dlBase   string // base URL for authed calls (login may hand back a VIP host)
}

// NewOpenSubtitles builds a client. Any credential may be empty; callers gate on
// Configured().
func NewOpenSubtitles(apiKey, username, password string) *OpenSubtitles {
	return &OpenSubtitles{
		apiKey:     apiKey,
		username:   username,
		password:   password,
		http:       &http.Client{Timeout: 20 * time.Second},
		searchBase: defaultOSBaseURL,
		dlBase:     defaultOSBaseURL,
	}
}

// Configured reports whether external subtitle fetch is usable end-to-end
// (search + download). Download needs a login, so all three credentials matter.
func (c *OpenSubtitles) Configured() bool {
	return c.apiKey != "" && c.username != "" && c.password != ""
}

// Query is a subtitle search. Provide as many identifiers as known; moviehash
// yields the most accurate (release-exact) matches.
type Query struct {
	TMDBID       int64    // movie TMDB id
	ParentTMDBID int64    // series TMDB id (for episodes)
	Season       int      // episode season number (with ParentTMDBID)
	Episode      int      // episode number
	MovieHash    string   // OpenSubtitles moviehash of the exact file
	Languages    []string // ISO-639 codes; empty → ["en"]
}

// Subtitle is one search result. FileID is the handle passed to Download.
type Subtitle struct {
	FileID          int64
	Language        string
	Release         string
	HearingImpaired bool
	MovieHashMatch  bool
	DownloadCount   int
}

// Search returns subtitle candidates ordered best-first: exact moviehash matches
// ahead of the rest, then by download popularity.
func (c *OpenSubtitles) Search(ctx context.Context, q Query) ([]Subtitle, error) {
	langs := q.Languages
	if len(langs) == 0 {
		langs = []string{"en"}
	}
	v := url.Values{}
	v.Set("languages", strings.ToLower(strings.Join(langs, ",")))
	if q.MovieHash != "" {
		v.Set("moviehash", q.MovieHash)
	}
	switch {
	case q.ParentTMDBID > 0 && q.Episode > 0:
		v.Set("parent_tmdb_id", strconv.FormatInt(q.ParentTMDBID, 10))
		v.Set("season_number", strconv.Itoa(q.Season))
		v.Set("episode_number", strconv.Itoa(q.Episode))
	case q.TMDBID > 0:
		v.Set("tmdb_id", strconv.FormatInt(q.TMDBID, 10))
	case q.MovieHash == "":
		return nil, fmt.Errorf("subtitle search: no usable identifier (tmdb/parent_tmdb/moviehash)")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.searchBase+"/subtitles?"+v.Encode(), nil)
	if err != nil {
		return nil, err
	}
	c.setHeaders(req, false)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, apiError("search", resp)
	}

	var body struct {
		Data []struct {
			Attributes struct {
				Language        string `json:"language"`
				DownloadCount   int    `json:"download_count"`
				HearingImpaired bool   `json:"hearing_impaired"`
				MovieHashMatch  bool   `json:"moviehash_match"`
				Release         string `json:"release"`
				Files           []struct {
					FileID int64 `json:"file_id"`
				} `json:"files"`
			} `json:"attributes"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("decode subtitle search: %w", err)
	}

	out := make([]Subtitle, 0, len(body.Data))
	for _, d := range body.Data {
		if len(d.Attributes.Files) == 0 {
			continue
		}
		out = append(out, Subtitle{
			FileID:          d.Attributes.Files[0].FileID,
			Language:        d.Attributes.Language,
			Release:         d.Attributes.Release,
			HearingImpaired: d.Attributes.HearingImpaired,
			MovieHashMatch:  d.Attributes.MovieHashMatch,
			DownloadCount:   d.Attributes.DownloadCount,
		})
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].MovieHashMatch != out[j].MovieHashMatch {
			return out[i].MovieHashMatch // hash matches first
		}
		return out[i].DownloadCount > out[j].DownloadCount
	})
	return out, nil
}

// Download resolves a file_id to its subtitle bytes (SRT). It logs in if needed,
// asks the API for a time-limited link, then fetches it.
func (c *OpenSubtitles) Download(ctx context.Context, fileID int64) ([]byte, error) {
	if err := c.ensureToken(ctx); err != nil {
		return nil, err
	}

	reqBody, _ := json.Marshal(map[string]any{"file_id": fileID})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base()+"/download", bytes.NewReader(reqBody))
	if err != nil {
		return nil, err
	}
	c.setHeaders(req, true)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, apiError("download", resp)
	}
	var dl struct {
		Link      string `json:"link"`
		Remaining int    `json:"remaining"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&dl); err != nil {
		return nil, fmt.Errorf("decode download response: %w", err)
	}
	if dl.Link == "" {
		return nil, fmt.Errorf("download: empty link (quota exhausted?)")
	}

	fetch, err := http.NewRequestWithContext(ctx, http.MethodGet, dl.Link, nil)
	if err != nil {
		return nil, err
	}
	fetch.Header.Set("User-Agent", osUserAgent)
	fr, err := c.http.Do(fetch)
	if err != nil {
		return nil, err
	}
	defer func() { _ = fr.Body.Close() }()
	if fr.StatusCode != http.StatusOK {
		return nil, apiError("fetch", fr)
	}
	return io.ReadAll(io.LimitReader(fr.Body, 8<<20)) // subtitles are tiny; cap at 8 MiB
}

// ensureToken logs in when there's no fresh JWT. Login is expensive, so the
// token is cached for tokenTTL and reused across downloads.
func (c *OpenSubtitles) ensureToken(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token != "" && time.Now().Before(c.tokenExp) {
		return nil
	}

	reqBody, _ := json.Marshal(map[string]string{"username": c.username, "password": c.password})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, defaultOSBaseURL+"/login", bytes.NewReader(reqBody))
	if err != nil {
		return err
	}
	c.setHeaders(req, false)

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return apiError("login", resp)
	}
	var body struct {
		Token   string `json:"token"`
		BaseURL string `json:"base_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return fmt.Errorf("decode login: %w", err)
	}
	if body.Token == "" {
		return fmt.Errorf("login: no token returned")
	}
	c.token = body.Token
	c.tokenExp = time.Now().Add(tokenTTL)
	// Login may route us to a VIP host for authed calls.
	if body.BaseURL != "" {
		c.dlBase = "https://" + strings.TrimPrefix(body.BaseURL, "https://") + "/api/v1"
	}
	return nil
}

func (c *OpenSubtitles) base() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.dlBase != "" {
		return c.dlBase
	}
	return defaultOSBaseURL
}

func (c *OpenSubtitles) setHeaders(req *http.Request, auth bool) {
	req.Header.Set("Api-Key", c.apiKey)
	req.Header.Set("User-Agent", osUserAgent)
	req.Header.Set("Accept", "application/json")
	if req.Method == http.MethodPost {
		req.Header.Set("Content-Type", "application/json")
	}
	if auth {
		c.mu.Lock()
		tok := c.token
		c.mu.Unlock()
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
	}
}

func apiError(op string, resp *http.Response) error {
	snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
	return fmt.Errorf("opensubtitles %s: status %d: %s", op, resp.StatusCode, strings.TrimSpace(string(snippet)))
}
