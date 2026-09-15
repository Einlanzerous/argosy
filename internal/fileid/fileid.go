// Package fileid names what a media file currently contains, so that anything
// derived from the file can key on it rather than on the catalog id.
//
// An item keeps its id when its file is replaced (ARGY-238): a Sonarr upgrade
// re-points the existing row at the new file instead of minting a new one, so
// watched state and stowed copies survive. The cost is that the id no longer
// implies one file. Every cache built from the file — extracted captions, the
// OpenSubtitles search, a live transcode session, a stow package — has to be
// told the file changed, and this package is the single place the string they
// compare is formatted. Two formatters that disagree about one fallback would
// make every live cache directory read as an orphan and be swept every hour,
// with nothing failing loudly.
package fileid

import "strconv"

// Unknown is the identity of a file nothing is known about: no hash, no size.
const Unknown = "unknown"

// Identity returns the file's content hash, falling back to its size (prefixed
// "s", so it can never collide with a hex hash) and then to Unknown.
//
// The hash covers the first MiB, so it changes when a replacement differs there
// — which a re-encode always does, and a same-name repack almost always does.
func Identity(contentHash *string, fileSize *int64) string {
	if contentHash != nil && *contentHash != "" {
		return *contentHash
	}
	if fileSize != nil {
		return "s" + strconv.FormatInt(*fileSize, 10)
	}
	return Unknown
}

// ItemKey is the top-level cache key for one item's file: the id and the
// identity together, flat, because Ballast reclaims only top-level entries of a
// cache directory. An empty identity is treated as Unknown.
func ItemKey(itemID, identity string) string {
	if identity == "" {
		identity = Unknown
	}
	return itemID + "-" + identity
}
