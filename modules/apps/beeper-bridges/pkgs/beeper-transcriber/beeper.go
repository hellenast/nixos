package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

const (
	beeperAPI       = "https://api.beeper.com"
	beeperMatrixURL = "https://matrix.beeper.com"
	// The same placeholder auth Beeper's own bridge manager (bbctl) sends
	// for the login endpoints, which take no account token.
	beeperLoginAuth = "BEEPER-PRIVATE-API-PLEASE-DONT-USE"
)

// session is what `login` saves for `run`: the Matrix login, and the key the
// crypto store's secrets are encrypted with.
type session struct {
	UserID      id.UserID   `json:"user_id"`
	DeviceID    id.DeviceID `json:"device_id"`
	AccessToken string      `json:"access_token"`
	PickleKey   []byte      `json:"pickle_key"`
}

func sessionPath(cfg config) string  { return filepath.Join(cfg.stateDir, "session.json") }
func cryptoDBPath(cfg config) string { return filepath.Join(cfg.stateDir, "crypto.db") }

func loadSession(cfg config) (*session, error) {
	data, err := os.ReadFile(sessionPath(cfg))
	if err != nil {
		return nil, fmt.Errorf("no saved login (run `beeper-transcriber login` first): %w", err)
	}
	var s session
	return &s, json.Unmarshal(data, &s)
}

func (s *session) save(cfg config) error {
	data, err := json.Marshal(s)
	if err != nil {
		return err
	}
	return os.WriteFile(sessionPath(cfg), data, 0o600)
}

// beeperRequest calls one of Beeper's account API endpoints, the ones its
// apps and bbctl use for the emailed-code login.
func beeperRequest(ctx context.Context, path string, body, into any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, beeperAPI+path, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+beeperLoginAuth)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		var errBody struct {
			Error string `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&errBody)
		return fmt.Errorf("%s: HTTP %d %s", path, resp.StatusCode, errBody.Error)
	}
	if into == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(into)
}

func prompt(in *bufio.Reader, question string) (string, error) {
	fmt.Print(question)
	line, err := in.ReadString('\n')
	return strings.TrimSpace(line), err
}

// login signs in to Beeper the way bbctl does (email, then the emailed
// code), creates this program's own device with its encryption keys, and
// cross-signs that device with the account's recovery code. The bridges
// only share message keys with cross-signed devices, so without that last
// step every voice message would stay undecryptable.
func login(ctx context.Context, cfg config) error {
	if _, err := os.Stat(sessionPath(cfg)); err == nil {
		return fmt.Errorf("already logged in; delete %s (and crypto.db next to it) to log in again", sessionPath(cfg))
	}
	if err := os.MkdirAll(cfg.stateDir, 0o700); err != nil {
		return err
	}
	in := bufio.NewReader(os.Stdin)

	email, err := prompt(in, "Beeper account email: ")
	if err != nil {
		return err
	}
	var start struct {
		RequestID string `json:"request"`
	}
	if err = beeperRequest(ctx, "/user/login", struct{}{}, &start); err != nil {
		return fmt.Errorf("starting login: %w", err)
	}
	// appType "bbctl": the value Beeper's self-hosting tool sends, which is
	// what this is.
	if err = beeperRequest(ctx, "/user/login/email", map[string]any{
		"request": start.RequestID, "email": email, "appType": "bbctl", "onlyExistingAccounts": true,
	}, nil); err != nil {
		return fmt.Errorf("sending login email: %w", err)
	}
	code, err := prompt(in, "Code from the email: ")
	if err != nil {
		return err
	}
	var loggedIn struct {
		Token string `json:"token"`
	}
	if err = beeperRequest(ctx, "/user/login/response", map[string]any{
		"request": start.RequestID, "response": code, "appType": "bbctl", "onlyExistingAccounts": true,
	}, &loggedIn); err != nil {
		return fmt.Errorf("checking login code: %w", err)
	}

	client, err := mautrix.NewClient(beeperMatrixURL, "", "")
	if err != nil {
		return err
	}
	client.Log = logger
	resp, err := client.Login(ctx, &mautrix.ReqLogin{
		Type:                     "org.matrix.login.jwt",
		Token:                    loggedIn.Token,
		InitialDeviceDisplayName: "beeper-transcriber",
		StoreCredentials:         true,
	})
	if err != nil {
		return fmt.Errorf("matrix login: %w", err)
	}
	sess := &session{UserID: resp.UserID, DeviceID: resp.DeviceID, AccessToken: resp.AccessToken, PickleKey: make([]byte, 32)}
	if _, err = rand.Read(sess.PickleKey); err != nil {
		return err
	}
	// Saved before the crypto setup, so a failure below doesn't strand a
	// device on the account that nothing can use or log out.
	if err = sess.save(cfg); err != nil {
		return err
	}
	fmt.Printf("Logged in as %s (device %s).\n", sess.UserID, sess.DeviceID)

	helper, err := setupCrypto(ctx, cfg, client, sess)
	if err != nil {
		return err
	}
	defer helper.Close()
	recoveryCode, err := prompt(in, "Recovery code (Beeper Settings > Security): ")
	if err != nil {
		return err
	}
	if err = helper.Machine().VerifyWithRecoveryKey(ctx, recoveryCode); err != nil {
		return fmt.Errorf("verifying this device with the recovery code: %w", err)
	}
	fmt.Println("Device verified. Start the service (or `beeper-transcriber run`).")
	return nil
}
