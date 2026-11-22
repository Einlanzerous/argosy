package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/user"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/db"
)

// runServiceToken implements `argosy service-token mint|revoke|list` (ARGY-325):
// the host-side way to issue and withdraw the scoped credential another service
// (Satlink) uses to read the sessions summary. There is deliberately no HTTP
// route for any of it: a token that can be minted over the API could be minted
// by whatever the API was compromised through.
func runServiceToken(cfg config.Config, logger *slog.Logger, args []string) {
	if cfg.DatabaseURL == "" {
		logger.Error("no database configured (set ARGOSY_DATABASE_URL or ARGOSY_DB_HOST)")
		os.Exit(1)
	}
	ctx := context.Background()
	if err := db.Migrate(ctx, cfg.DatabaseURL); err != nil {
		logger.Error("migrate failed", "err", err)
		os.Exit(1)
	}
	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("database connection failed", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	osUser := "unknown"
	if u, err := user.Current(); err == nil {
		osUser = u.Username
	}
	if err := serviceTokenCmd(ctx, auth.NewStore(pool), os.Stdout, osUser, args); err != nil {
		fmt.Fprintln(os.Stderr, "service-token:", err)
		os.Exit(1)
	}
}

const serviceTokenUsage = `usage:
  argosy service-token mint   -label <label> -scope sessions:summary
  argosy service-token revoke -id <id> | -label <label>
  argosy service-token list`

// serviceTokenCmd is the testable body of runServiceToken. The plaintext is
// written to out exactly once, by mint, and nothing else here can print it.
func serviceTokenCmd(ctx context.Context, store *auth.Store, out io.Writer, osUser string, args []string) error {
	if len(args) == 0 {
		return errors.New(serviceTokenUsage)
	}
	fset := flag.NewFlagSet("service-token "+args[0], flag.ContinueOnError)
	fset.SetOutput(io.Discard)
	switch args[0] {
	case "mint":
		label := fset.String("label", "", "consumer label, e.g. satlink")
		scope := fset.String("scope", "", "scope: "+auth.ScopeSessionsSummary)
		if err := fset.Parse(args[1:]); err != nil {
			return fmt.Errorf("%w\n%s", err, serviceTokenUsage)
		}
		plaintext, tok, err := store.MintServiceToken(ctx, *label, *scope, osUser)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintf(out, "id:    %s\nlabel: %s\nscope: %s\ntoken: %s\n\nThis is the only time the token is shown; it is not stored.\n",
			tok.ID, tok.ConsumerLabel, tok.Scope, plaintext)
		return err
	case "revoke":
		id := fset.String("id", "", "token id")
		label := fset.String("label", "", "revoke every live token with this label")
		if err := fset.Parse(args[1:]); err != nil {
			return fmt.Errorf("%w\n%s", err, serviceTokenUsage)
		}
		ids, err := store.RevokeServiceTokens(ctx, *id, *label, osUser)
		if err != nil {
			return err
		}
		for _, id := range ids {
			if _, err := fmt.Fprintf(out, "revoked %s\n", id); err != nil {
				return err
			}
		}
		return nil
	case "list":
		if err := fset.Parse(args[1:]); err != nil {
			return fmt.Errorf("%w\n%s", err, serviceTokenUsage)
		}
		toks, err := store.ListServiceTokens(ctx)
		if err != nil {
			return err
		}
		tw := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
		var b strings.Builder
		b.WriteString("ID\tLABEL\tSCOPE\tCREATED\tLAST USED\tREVOKED\n")
		for _, t := range toks {
			fmt.Fprintf(&b, "%s\t%s\t%s\t%s\t%s\t%s\n", t.ID, t.ConsumerLabel, t.Scope,
				t.CreatedAt.UTC().Format(time.RFC3339), tsOrDash(t.LastUsedAt), tsOrDash(t.RevokedAt))
		}
		if _, err := io.WriteString(tw, b.String()); err != nil {
			return err
		}
		return tw.Flush()
	default:
		return errors.New(serviceTokenUsage)
	}
}

func tsOrDash(t *time.Time) string {
	if t == nil {
		return "-"
	}
	return t.UTC().Format(time.RFC3339)
}
