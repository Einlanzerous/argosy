package stevedore

import "strings"

// pathTagSegments maps a lowercased path segment to a tag. The legacy library
// layout used top-level category directories (notably `anime/`) that we no
// longer model as kinds — a file under `anime/` might be a series OR a film.
// We surface those segments as tags instead, so an anime film stays a film
// (kind=movie) while remaining findable as `anime`.
var pathTagSegments = map[string]string{
	"anime": "anime",
}

// deriveTags returns the distinct tags implied by a media file's relative path,
// in first-seen order. Empty when no recognized segment is present.
func deriveTags(filePath string) []string {
	seen := map[string]bool{}
	var tags []string
	for _, seg := range strings.Split(filePath, "/") {
		if tag, ok := pathTagSegments[strings.ToLower(seg)]; ok && !seen[tag] {
			seen[tag] = true
			tags = append(tags, tag)
		}
	}
	return tags
}
