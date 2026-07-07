package subtitle

import "strings"

// iso6392to1 maps the ISO 639-2 (three-letter) codes ffprobe emits to the
// ISO 639-1 (two-letter) codes a WebVTT <track srclang> expects. Only common
// languages are listed; unknown codes pass through unchanged.
var iso6392to1 = map[string]string{
	"eng": "en", "spa": "es", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de",
	"ita": "it", "por": "pt", "rus": "ru", "jpn": "ja", "chi": "zh", "zho": "zh",
	"kor": "ko", "ara": "ar", "dut": "nl", "nld": "nl", "pol": "pl", "swe": "sv",
	"nor": "no", "dan": "da", "fin": "fi", "tur": "tr", "heb": "he", "hin": "hi",
	"tha": "th", "vie": "vi", "ces": "cs", "cze": "cs", "gre": "el", "ell": "el",
	"hun": "hu", "ind": "id", "ron": "ro", "rum": "ro", "ukr": "uk",
}

// langNames maps ISO 639-1 codes to display names for the subtitle picker.
var langNames = map[string]string{
	"en": "English", "es": "Spanish", "fr": "French", "de": "German",
	"it": "Italian", "pt": "Portuguese", "ru": "Russian", "ja": "Japanese",
	"zh": "Chinese", "ko": "Korean", "ar": "Arabic", "nl": "Dutch",
	"pl": "Polish", "sv": "Swedish", "no": "Norwegian", "da": "Danish",
	"fi": "Finnish", "tr": "Turkish", "he": "Hebrew", "hi": "Hindi",
	"th": "Thai", "vi": "Vietnamese", "cs": "Czech", "el": "Greek",
	"hu": "Hungarian", "id": "Indonesian", "ro": "Romanian", "uk": "Ukrainian",
}

// langCode normalizes a subtitle language tag to a BCP-47 code where possible.
func langCode(tag string) string {
	tag = strings.ToLower(strings.TrimSpace(tag))
	if tag == "" {
		return "und"
	}
	if two, ok := iso6392to1[tag]; ok {
		return two
	}
	return tag
}

// langName returns a human-readable language name, falling back to the code.
func langName(code string) string {
	if name, ok := langNames[code]; ok {
		return name
	}
	if code == "" || code == "und" {
		return "Unknown"
	}
	return strings.ToUpper(code)
}

// LangCode exposes the shared normalization to other packages (the library's
// audio-track enumerator, ARGY-126) so audio-rendition language codes match the
// format subtitles use — which is what makes the per-device audioLanguage
// preference auto-select the right track.
func LangCode(tag string) string { return langCode(tag) }
