package stevedore

import "encoding/xml"

// Kodi-style NFO parsing. Each parser returns an override map with only the
// fields present in the file: title, overview (plot), year, genres.

type movieNFO struct {
	XMLName xml.Name `xml:"movie"`
	Title   string   `xml:"title"`
	Plot    string   `xml:"plot"`
	Year    int      `xml:"year"`
	Genres  []string `xml:"genre"`
}

type tvShowNFO struct {
	XMLName xml.Name `xml:"tvshow"`
	Title   string   `xml:"title"`
	Plot    string   `xml:"plot"`
	Year    int      `xml:"year"`
	Genres  []string `xml:"genre"`
}

type episodeNFO struct {
	XMLName xml.Name `xml:"episodedetails"`
	Title   string   `xml:"title"`
	Plot    string   `xml:"plot"`
	Genres  []string `xml:"genre"`
}

func parseMovieNFO(data []byte) (map[string]any, error) {
	var n movieNFO
	if err := xml.Unmarshal(data, &n); err != nil {
		return nil, err
	}
	return nfoOverride(n.Title, n.Plot, n.Year, n.Genres), nil
}

func parseTVShowNFO(data []byte) (map[string]any, error) {
	var n tvShowNFO
	if err := xml.Unmarshal(data, &n); err != nil {
		return nil, err
	}
	return nfoOverride(n.Title, n.Plot, n.Year, n.Genres), nil
}

func parseEpisodeNFO(data []byte) (map[string]any, error) {
	var n episodeNFO
	if err := xml.Unmarshal(data, &n); err != nil {
		return nil, err
	}
	return nfoOverride(n.Title, n.Plot, 0, n.Genres), nil
}

func nfoOverride(title, plot string, year int, genres []string) map[string]any {
	o := map[string]any{}
	if title != "" {
		o["title"] = title
	}
	if plot != "" {
		o["overview"] = plot
	}
	if year > 0 {
		o["year"] = year
	}
	if len(genres) > 0 {
		o["genres"] = genres
	}
	return o
}
