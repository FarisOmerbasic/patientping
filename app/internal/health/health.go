// Package health lets a program check its own /healthz. The images have no
// shell and no curl, so the program itself is the container's health check.
package health

import (
	"fmt"
	"net/http"
	"time"
)

// Check asks http://localhost:<port>/healthz and returns nil only for a 200.
// Inside a container, localhost is that container itself.
func Check(port string) error {
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://localhost:" + port + "/healthz")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthz answered %d", resp.StatusCode)
	}
	return nil
}
