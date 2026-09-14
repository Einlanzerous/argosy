package fileid

import "testing"

func TestIdentity(t *testing.T) {
	hash := "3f2a9c"
	empty := ""
	size := int64(1 << 30)
	zero := int64(0)

	cases := []struct {
		name string
		hash *string
		size *int64
		want string
	}{
		{"hash wins over size", &hash, &size, "3f2a9c"},
		{"hash alone", &hash, nil, "3f2a9c"},
		{"size when the hash is missing", nil, &size, "s1073741824"},
		{"an empty hash is no hash", &empty, &size, "s1073741824"},
		{"a zero size is still a size", nil, &zero, "s0"},
		{"nothing known", nil, nil, Unknown},
		{"empty hash and no size", &empty, nil, Unknown},
	}
	for _, c := range cases {
		if got := Identity(c.hash, c.size); got != c.want {
			t.Errorf("%s: Identity = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestItemKey(t *testing.T) {
	if got := ItemKey("item", "3f2a9c"); got != "item-3f2a9c" {
		t.Errorf("ItemKey = %q, want item-3f2a9c", got)
	}
	if got := ItemKey("item", ""); got != "item-"+Unknown {
		t.Errorf("ItemKey with no identity = %q, want item-%s", got, Unknown)
	}
}
