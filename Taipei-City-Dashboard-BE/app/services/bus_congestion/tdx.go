package bus_congestion

import (
	"TaipeiCityDashboardBE/global"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"
)

const tdxTokenURL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"

type tdxTokenCache struct {
	mu        sync.Mutex
	token     string
	expiresAt time.Time
}

var tdxToken = &tdxTokenCache{}

func getTDXToken() (string, error) {
	tdxToken.mu.Lock()
	defer tdxToken.mu.Unlock()

	if time.Now().Before(tdxToken.expiresAt.Add(-60*time.Second)) && tdxToken.token != "" {
		return tdxToken.token, nil
	}

	data := url.Values{}
	data.Set("grant_type", "client_credentials")
	data.Set("client_id", global.TDXClientID)
	data.Set("client_secret", global.TDXClientSecret)

	resp, err := http.PostForm(tdxTokenURL, data)
	if err != nil {
		return "", fmt.Errorf("TDX token request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("TDX token parse failed: %w", err)
	}

	tdxToken.token = result.AccessToken
	tdxToken.expiresAt = time.Now().Add(time.Duration(result.ExpiresIn) * time.Second)
	return tdxToken.token, nil
}
