package auth

import (
	"context"
	"errors"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func testStore(t *testing.T) (*Store, context.Context) {
	t.Helper()
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run auth tests")
	}
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return NewStore(pool), ctx
}

func uniqueUsername() string {
	return "test_" + strconv.FormatInt(time.Now().UnixNano(), 36)
}

func TestAuthFlow(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername() // computed, not a static secret

	if _, err := store.CreateAccount(ctx, username, password, "Test Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}

	if _, err := store.Login(ctx, username, "wrong"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("login wrong pw: got %v, want ErrInvalidCredentials", err)
	}
	if _, err := store.Login(ctx, "ghost_"+username, password); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("login unknown user: got %v, want ErrInvalidCredentials", err)
	}

	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if len(login.Profiles) != 1 || login.Profiles[0].Role != api.Admin {
		t.Fatalf("expected one admin profile, got %+v", login.Profiles)
	}
	adminProfile := login.Profiles[0].Id

	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username:   username,
		Password:   password,
		UserId:     adminProfile,
		DeviceName: "Test TV",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}
	if reg.Token == "" {
		t.Fatal("expected a device token")
	}

	sess, err := store.AuthenticateDevice(ctx, reg.Token)
	if err != nil {
		t.Fatalf("authenticate device: %v", err)
	}
	if sess.AccountId != login.Account.Id {
		t.Errorf("session account = %v, want %v", sess.AccountId, login.Account.Id)
	}
	if sess.UserId != adminProfile || sess.Role != api.Admin {
		t.Errorf("session user/role = %v/%v, want %v/admin", sess.UserId, sess.Role, adminProfile)
	}

	if _, err := store.AuthenticateDevice(ctx, "not-a-real-token"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("bad token: got %v, want ErrInvalidCredentials", err)
	}

	devices, err := store.ListDevices(ctx, login.Account.Id)
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}
	if len(devices) != 1 || devices[0].Revoked {
		t.Fatalf("expected one active device, got %+v", devices)
	}

	if err := store.RevokeDevice(ctx, sess, reg.Device.Id); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("after revoke: got %v, want ErrInvalidCredentials", err)
	}
}
