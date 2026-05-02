package ai

import (
	"TaipeiCityDashboardBE/app/models"
	"fmt"
	"strings"
	"sync/atomic"
	"time"
)

type catalogueEntry struct {
	markdown string
	builtAt  time.Time
}

var catalogueCache atomic.Pointer[catalogueEntry]

const catalogueTTL = 5 * time.Minute

// DashboardCatalogueMarkdown returns a Markdown listing of all catalogue dashboards.
// Result is cached for catalogueTTL to avoid repeated DB queries.
func DashboardCatalogueMarkdown() string {
	if e := catalogueCache.Load(); e != nil && time.Since(e.builtAt) < catalogueTTL {
		return e.markdown
	}
	rows, err := models.GetCatalogueRows()
	if err != nil || len(rows) == 0 {
		return ""
	}
	var sb strings.Builder
	for _, r := range rows {
		fmt.Fprintf(&sb, "- index=`%s` city=`%s` name=\"%s\"\n", r.Index, r.City, r.Name)
		if len(r.ComponentTitles) > 0 {
			fmt.Fprintf(&sb, "  components: %s\n", strings.Join(r.ComponentTitles, ", "))
		}
	}
	md := sb.String()
	catalogueCache.Store(&catalogueEntry{markdown: md, builtAt: time.Now()})
	return md
}

// InvalidateCatalogue forces the next DashboardCatalogueMarkdown call to rebuild from DB.
func InvalidateCatalogue() {
	catalogueCache.Store(nil)
}
