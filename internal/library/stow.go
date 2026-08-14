package library

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/stow"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Stow methods, mirroring the StowJob.method enum. Passthrough hands over the
// source file untouched; package re-encodes it into one offline-friendly MP4.
const (
	stowPassthrough = "passthrough"
	stowPackage     = "package"
)

// DefaultStowPassthroughMax is the size ceiling for handing over a source file
// untouched. Above it, packaging is worth the encode: a 4K remux in this library
// runs 20–60 GB, and the whole point of Stow is fitting a film onto a phone
// before a flight. Overridable via ARGOSY_STOW_PASSTHROUGH_MAX.
const DefaultStowPassthroughMax int64 = 4 << 30 // 4 GiB

// Codecs a phone or tablet can be relied on to decode from a local file, with no
// network to fall back on if it can't. Deliberately narrower than the streaming
// path's sets: a stowed file that won't open is a dead end, not a quality
// regression, so anything whose device support is uneven (AV1, VP9 on iOS, DTS,
// TrueHD, AC-3) is packaged rather than gambled on.
var (
	stowVideo = map[string]bool{"h264": true, "avc1": true}
	stowAudio = map[string]bool{"aac": true, "mp3": true, "opus": true, "vorbis": true, "flac": true}
	// Containers every mobile player opens. Matroska is the big one missing here
	// and is admitted separately, per client (ExoPlayer yes, AVPlayer no).
	stowContainers = map[string]bool{".mp4": true, ".m4v": true, ".mov": true, ".webm": true}
)

// stowPlan is the resolved decision for one stow request.
type stowPlan struct {
	method string
	reason string
}

// planStow decides whether an item can be handed to a device as-is or has to be
// packaged first. It is the offline sibling of planPlayback, and it inverts that
// function's bias: planPlayback copies whenever it can, preserving resolution and
// HDR, because a client that mis-negotiates can renegotiate mid-session. Here
// there is no renegotiating — the file has to play on a plane — so the question
// is not "what is the best this device could manage" but "what will certainly
// work, at a size worth carrying".
//
// clientHEVC and clientMatroska come from the device rather than being assumed:
// most of a real library is HEVC in Matroska, so those two answers decide whether
// a stow is instant or a twenty-minute encode, and they differ by platform
// (Android/ExoPlayer plays both; iOS/AVPlayer plays neither in a local file).
func planStow(ext, videoCodec, audioCodec string, highBitDepth bool, sizeBytes, maxBytes int64, clientHEVC, clientMatroska bool) stowPlan {
	ext = strings.ToLower(ext)
	v := strings.ToLower(videoCodec)
	a := strings.ToLower(audioCodec)

	pkg := func(reason string) stowPlan { return stowPlan{method: stowPackage, reason: reason} }

	// A phone decodes H.264 unconditionally, and HEVC when it says it can.
	videoOK := stowVideo[v] || (clientHEVC && isHEVC(v))

	switch {
	case maxBytes > 0 && sizeBytes > maxBytes:
		return pkg(fmt.Sprintf("the source is %s; packaging a smaller copy", humanBytes(sizeBytes)))
	case !videoOK:
		if isHEVC(v) {
			return pkg("this device doesn't decode HEVC; re-encoding to H.264")
		}
		return pkg("the " + videoCodec + " video codec needs re-encoding for offline playback")
	// 10-bit H.264 (High 10) stays blocked even for an HEVC-capable client: mobile
	// hardware support for it is far thinner than for HEVC Main 10, and the same
	// reasoning planPlayback applies holds here with no fallback available.
	case highBitDepth && (v == "h264" || v == "avc1"):
		return pkg("10-bit H.264 decodes unreliably on mobile; re-encoding to 8-bit")
	case a != "" && !stowAudio[a]:
		return pkg("the " + audioCodec + " audio track needs re-encoding to AAC")
	case ext == ".mkv" && !clientMatroska:
		return pkg("this device can't open the Matroska container; repackaging as MP4")
	case ext != ".mkv" && !stowContainers[ext]:
		return pkg("the " + strings.TrimPrefix(ext, ".") + " container needs repackaging as MP4")
	}
	return stowPlan{method: stowPassthrough, reason: "the original file plays offline as-is"}
}

// humanBytes formats a size for a user-facing reason string.
func humanBytes(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGT"[exp])
}

// stowSource is a transcodeSource plus the facts the stow decision needs that
// playback doesn't: how big the file actually is, and how long it runs.
type stowSource struct {
	transcodeSource
	sizeBytes       int64
	durationSeconds float64
}

// itemStowSource resolves an item's media path, codecs, size and duration.
func (s *Store) itemStowSource(ctx context.Context, accountID, itemID string) (stowSource, bool, error) {
	src, ok, err := s.itemSource(ctx, accountID, itemID)
	if err != nil || !ok {
		return stowSource{}, ok, err
	}
	out := stowSource{transcodeSource: src}

	var duration *float64
	err = s.pool.QueryRow(ctx,
		`SELECT mi.duration_seconds
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.id = $2`, accountID, itemID).Scan(&duration)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return stowSource{}, false, err
	}
	if duration != nil {
		out.durationSeconds = *duration
	}

	fi, err := os.Stat(src.path)
	if err != nil {
		// The catalog row outlived the file (a mount dropped, ARGY-96's rename
		// case). Treat it as absent rather than stowing something unreadable.
		return stowSource{}, false, nil
	}
	out.sizeBytes = fi.Size()
	return out, true, nil
}

// stowItem decides how an item reaches the device for offline viewing, and
// starts a packaging job when one is needed.
func (h *handlers) stowItem(w http.ResponseWriter, r *http.Request) {
	// Same two scopes as a transcode: the item is resolved against the server's
	// catalog (the owner's libraries), while the job belongs to the caller's own
	// household account.
	account := accountOf(r)
	itemID := r.PathValue("itemId")

	src, ok, err := h.store.itemStowSource(r.Context(), catalogOf(r), itemID)
	if errors.Is(err, ErrPathTraversal) {
		httpx.Error(w, http.StatusForbidden, "forbidden")
		return
	}
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}

	var body api.StowRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}
	clientHEVC := body.Hevc != nil && *body.Hevc
	clientMatroska := body.Matroska != nil && *body.Matroska

	ext := strings.ToLower(filepath.Ext(src.path))
	plan := planStow(ext, src.video, src.audio, src.highBitDepth, src.sizeBytes,
		h.stowPassthroughMax, clientHEVC, clientMatroska)
	h.logger.Info("stow decision", "item", itemID, "method", plan.method, "reason", plan.reason,
		"container", ext, "video", src.video, "audio", src.audio, "bytes", src.sizeBytes,
		"highBitDepth", src.highBitDepth, "clientHevc", clientHEVC, "clientMatroska", clientMatroska)

	itemUUID, _ := uuid.Parse(itemID)
	if plan.method == stowPassthrough {
		// Nothing to make and nothing to track: the existing stream endpoint
		// already serves these bytes with range support and token auth.
		url := "/api/v1/items/" + itemID + "/stream"
		httpx.JSON(w, http.StatusAccepted, api.StowJob{
			ItemId:          itemUUID,
			Method:          api.Passthrough,
			State:           api.StowJobStateReady,
			DownloadUrl:     &url,
			Bytes:           &src.sizeBytes,
			DurationSeconds: &src.durationSeconds,
			Reason:          &plan.reason,
		})
		return
	}

	if h.stow == nil {
		httpx.Error(w, http.StatusServiceUnavailable, "offline packaging is not enabled on this server")
		return
	}
	job, err := h.stow.Request(r.Context(), stow.Request{
		AccountID:       account,
		ItemID:          itemID,
		Source:          src.path,
		SourceHeight:    src.height,
		DurationSeconds: src.durationSeconds,
		AudioTracks:     src.audioTracks,
	})
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusAccepted, toAPIStowJob(job, &plan.reason))
}

// listStowJobs returns the packaging jobs owned by the current account.
func (h *handlers) listStowJobs(w http.ResponseWriter, r *http.Request) {
	jobs, err := h.stow.List(r.Context(), accountOf(r))
	if err != nil {
		h.fail(w, err)
		return
	}
	out := make([]api.StowJob, 0, len(jobs))
	for _, j := range jobs {
		out = append(out, toAPIStowJob(j, nil))
	}
	httpx.JSON(w, http.StatusOK, out)
}

// getStowJob polls one packaging job.
func (h *handlers) getStowJob(w http.ResponseWriter, r *http.Request) {
	job, ok, err := h.stow.Get(r.Context(), accountOf(r), r.PathValue("jobId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	httpx.JSON(w, http.StatusOK, toAPIStowJob(job, nil))
}

// deleteStowJob cancels an in-flight package or releases a collected one.
func (h *handlers) deleteStowJob(w http.ResponseWriter, r *http.Request) {
	ok, err := h.stow.Delete(r.Context(), accountOf(r), r.PathValue("jobId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// stowFileHandler serves a ready package with byte-range support. Like the
// stream and subtitle endpoints it authenticates inline, because the download
// runs outside the API client — a resumable background transfer carries the
// per-device token as ?token= rather than a bearer header.
func stowFileHandler(mgr *stow.Manager, authStore *auth.Store, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := streamToken(r)
		if token == "" {
			httpx.Error(w, http.StatusUnauthorized, "missing token")
			return
		}
		sess, err := authStore.AuthenticateDevice(r.Context(), token)
		if err != nil {
			httpx.Error(w, http.StatusUnauthorized, "invalid or revoked token")
			return
		}
		jobID := r.PathValue("jobId")
		job, ok, err := mgr.Get(r.Context(), sess.AccountId.String(), jobID)
		if err != nil {
			logger.Error("stow: load job failed", "job", jobID, "err", err)
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		if !ok {
			httpx.Error(w, http.StatusNotFound, "not found")
			return
		}
		if job.State != stow.StateReady {
			httpx.Error(w, http.StatusConflict, "package is not ready yet")
			return
		}

		path := mgr.ArtifactPath(jobID)
		f, err := os.Open(path)
		if err != nil {
			httpx.Error(w, http.StatusNotFound, "file unavailable")
			return
		}
		defer func() { _ = f.Close() }()
		fi, err := f.Stat()
		if err != nil || fi.IsDir() {
			httpx.Error(w, http.StatusNotFound, "file unavailable")
			return
		}
		w.Header().Set("Content-Type", "video/mp4")
		w.Header().Set("Accept-Ranges", "bytes")
		// A finished package never changes, so a resumed download can safely
		// revalidate against this rather than restarting from byte zero.
		w.Header().Set("ETag", fmt.Sprintf("%q", fmt.Sprintf("%x-%x", fi.ModTime().UnixNano(), fi.Size())))
		http.ServeContent(w, r, fi.Name(), fi.ModTime(), f)
	}
}

// toAPIStowJob converts a packaging job to its API shape. reason is carried only
// on the response to the request that made the decision; polling a job later
// doesn't re-derive it.
func toAPIStowJob(j stow.Job, reason *string) api.StowJob {
	itemUUID, _ := uuid.Parse(j.ItemID)
	jobUUID, _ := uuid.Parse(j.ID)
	progress := float64(j.ProgressMS) / 1000
	out := api.StowJob{
		Id:              &jobUUID,
		ItemId:          itemUUID,
		Method:          api.Package,
		State:           api.StowJobState(j.State),
		DurationSeconds: &j.DurationSeconds,
		ProgressSeconds: &progress,
		CreatedAt:       &j.CreatedAt,
		Reason:          reason,
	}
	if j.State == stow.StateReady {
		url := "/api/v1/stow/" + j.ID + "/file"
		out.DownloadUrl = &url
		out.Bytes = &j.OutputBytes
		out.ReadyAt = j.ReadyAt
	}
	if j.Err != "" {
		out.Error = &j.Err
	}
	return out
}
