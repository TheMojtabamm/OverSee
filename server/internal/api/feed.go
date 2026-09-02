package api

import (
	"encoding/json"
	"net/http"
	"oversea/server/internal/store"
)

type FeedHandler struct {
	Store *store.Store
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// channelDTO renders a channel as the client expects in the feed.
func channelDTO(c store.Channel) map[string]any {
	item := map[string]any{
		"ref":         c.Ref,
		"title":       c.Title,
		"configCount": c.ConfigCount,
	}
	if c.TelegramURL != nil && *c.TelegramURL != "" {
		item["telegramUrl"] = *c.TelegramURL
	}
	return item
}

func (h *FeedHandler) ListChannels(w http.ResponseWriter, r *http.Request) {
	channels, err := h.Store.ActiveChannels(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	out := make([]map[string]any, 0, len(channels))
	for _, c := range channels {
		out = append(out, channelDTO(c))
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"channels": out})
}

func (h *FeedHandler) GetConfigs(w http.ResponseWriter, r *http.Request) {
	ref := r.PathValue("ref")
	channel, err := h.Store.ChannelByRef(r.Context(), ref)
	if err != nil {
		http.Error(w, "Channel not found", http.StatusNotFound)
		return
	}
	blobs, err := h.Store.ActiveBlobsForChannel(r.Context(), channel.ID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	configs := make([]map[string]string, len(blobs))
	for i, b := range blobs {
		configs[i] = map[string]string{"data": b.LockedBlob}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"configs": configs,
		"ad": map[string]string{
			"text":        deref(channel.AdText),
			"telegramUrl": deref(channel.TelegramURL),
		},
	})
}
