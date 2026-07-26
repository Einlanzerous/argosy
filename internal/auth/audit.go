package auth

import (
	"context"
	"encoding/json"
	"log/slog"

	"github.com/Einlanzerous/argosy/internal/api"
)

// Audit trail (ARGY-86). Every account/profile mutation appends a row to
// audit_log so "who did what, when" is answerable from the database — the gap
// the prod DB auth incident exposed. Rows carry no FKs on purpose: deleting an
// account must not erase the record of the deletion.

// Actor types recorded in audit_log.actor_type.
const (
	actorSession   = "session"   // a signed-in device (bearer session)
	actorProvision = "provision" // the X-Provision-Token caller (Purser)
)

type auditEntry struct {
	actorType      string
	actorAccountID string // empty for provision-token callers
	actorUserID    string // empty when the actor isn't a profile
	action         string // e.g. "account.disable", "profile.create"
	targetType     string // "account" | "profile"
	targetID       string
	detail         map[string]any
}

// sessionActor pre-fills the actor fields from a bearer session.
func sessionActor(sess api.Session) auditEntry {
	return auditEntry{
		actorType:      actorSession,
		actorAccountID: sess.AccountId.String(),
		actorUserID:    sess.UserId.String(),
	}
}

// audit appends e to the trail. Best-effort by design: the action itself has
// already happened (writes here are not transactional with it, matching how
// the rest of this store sequences its statements), so a failed insert must
// not fail the request — it is logged instead.
func (s *Store) audit(ctx context.Context, e auditEntry) {
	// The caller hands us the request context, which Go cancels the moment the
	// client disconnects — and the mutation has already committed by then. The
	// trail must survive a closed browser tab, so detach from cancellation.
	ctx = context.WithoutCancel(ctx)
	detail := e.detail
	if detail == nil {
		detail = map[string]any{}
	}
	detailJSON, err := json.Marshal(detail)
	if err != nil {
		detailJSON = []byte(`{}`)
	}
	_, err = s.pool.Exec(ctx,
		`INSERT INTO audit_log (actor_type, actor_account_id, actor_user_id, action, target_type, target_id, detail)
		 VALUES ($1, nullif($2, '')::uuid, nullif($3, '')::uuid, $4, $5, nullif($6, '')::uuid, $7)`,
		e.actorType, e.actorAccountID, e.actorUserID, e.action, e.targetType, e.targetID, detailJSON)
	if err != nil {
		slog.Warn("audit write failed", "action", e.action, "target", e.targetID, "err", err)
	}
}
