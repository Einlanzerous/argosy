package transcode

import "testing"

// TestSessionIDScopedToSourceIdentity: an item keeps its id when its file is
// replaced (ARGY-238), so a start after the replacement must not join a live
// encode of the old file — even when the replacement kept its filename.
func TestSessionIDScopedToSourceIdentity(t *testing.T) {
	base := StartRequest{ItemID: "i", AccountID: "acct-1", Source: "/m/Show S01E02.mkv",
		SourceIdentity: "hash-1", Encoder: EncoderSoftware}

	replaced := base
	replaced.SourceIdentity = "hash-2"
	if sessionID(base) == sessionID(replaced) {
		t.Error("a request for a replaced file (same path, new identity) joins the old file's session")
	}

	same := base
	if sessionID(base) != sessionID(same) {
		t.Error("identical requests no longer share a session")
	}
}
