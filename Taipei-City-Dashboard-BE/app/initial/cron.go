// Package initial contains functions that are run at the start of the application
package initial

import (
	"TaipeiCityDashboardBE/app/cache"
	"TaipeiCityDashboardBE/app/models"
	bus_congestion "TaipeiCityDashboardBE/app/services/bus_congestion"
	"TaipeiCityDashboardBE/logs"
	"context" // Add context import
	"time"

	"github.com/google/uuid" // Import the UUID library
	"github.com/robfig/cron/v3"
)

const ChatlogCleanupLockKey = "cron:chatlog_cleanup_lock"
// Lua script to atomically delete the key only if its value matches the token
const ReleaseLockScript = `
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
`

// InitCronJobs initializes and starts the scheduled tasks for the application.
func InitCronJobs() {
	logs.Info("Initializing cron jobs...")
	c := cron.New(
        cron.WithLocation(time.Local),
		cron.WithSeconds(),
    )

	// Schedule a daily task to clean up old chat logs.
	// The job runs once a day at midnight (server time).
	    _, err := c.AddFunc("@daily", func() { // Changed schedule to @daily
        // Create a context with a 10-minute timeout for the entire job.
        ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
        defer cancel() // Ensure context resources are released

		// Generate a unique token for this lock attempt (fencing token)
		token := uuid.New().String()

		// Try to acquire a distributed lock with a 1-hour expiration and the unique token as value.
		// This ensures that even if multiple instances are running, only one will execute the cleanup.
		lockAcquired, err := cache.Redis.SetNX(ChatlogCleanupLockKey, token, 1*time.Hour).Result()
		if err != nil {
			logs.Error("Error acquiring cron lock for chatlog cleanup:", err)
			return
		}

		// If the lock was not acquired, another instance is already running the job.
		if !lockAcquired {
			logs.Info("Cron job 'chatlog cleanup' skipped: lock not acquired.")
			return
		}

		// Lock acquired, proceed with the cleanup.
		// Defer the release of the lock using a Lua script to ensure it's freed only by its owner.
		defer func() {
			// Execute Lua script: delete key only if its value is still our token
			cmd := cache.Redis.Eval(ReleaseLockScript, []string{ChatlogCleanupLockKey}, token)
			if cmd.Err() != nil {
				logs.Error("Error releasing cron lock for chatlog cleanup:", cmd.Err())
			}
		}()


		logs.Info("Cron job 'chatlog cleanup' started...")
		// Pass the timeout context to the deletion function and capture deleted rows
        deletedRows, err := models.DeleteOldChatLogs(ctx, 6)
        if err != nil {
			logs.Error("Error during chatlog cleanup cron job:", err)
		} else {
			logs.FInfo("Cron job 'chatlog cleanup' finished successfully. Delete %d rows.", deletedRows)
		}
	})

	if err != nil {
		logs.Error("Failed to add chatlog cleanup cron job:", err)
		return
	}

	// Poll ETA every 2 minutes (6-field format: sec min hour dom month dow, required by WithSeconds())
	_, err = c.AddFunc("0 */2 * * * *", func() {
		ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
		defer cancel()
		bus_congestion.Service.Poll(ctx)
	})
	if err != nil {
		logs.Error("Failed to add bus_congestion_poll cron job:", err)
	}

	// Refresh map every 5 minutes
	_, err = c.AddFunc("0 */5 * * * *", func() {
		ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
		defer cancel()
		bus_congestion.Service.RefreshMap(ctx)
	})
	if err != nil {
		logs.Error("Failed to add bus_congestion_map cron job:", err)
	}

	// Refresh stop metadata daily
	_, err = c.AddFunc("@daily", func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()
		bus_congestion.Service.RefreshStops(ctx)
	})
	if err != nil {
		logs.Error("Failed to add bus_congestion_refresh_stops cron job:", err)
	}

	c.Start()
	logs.Info("Cron jobs started.")
}
