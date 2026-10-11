package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func boolEnv(key string) (bool, bool, error) {
	value, exists := os.LookupEnv(key)
	if !exists || strings.TrimSpace(value) == "" {
		return false, false, nil
	}
	parsed, err := strconv.ParseBool(strings.TrimSpace(value))
	return parsed, true, err
}

func main() {
	db := getenv("db", "/data/c2.db")
	if err := os.MkdirAll(filepath.Dir(db), 0700); err != nil {
		fmt.Fprintln(os.Stderr, "cannot create database directory:", err)
		os.Exit(1)
	}
	hostname := os.Getenv("fqdn")
	if hostname == "" {
		hostname = os.Getenv("POD_IP")
	}
	if hostname == "" {
		hostname = os.Getenv("POD_NAME")
	}
	if hostname == "" {
		hostname, _ = os.Hostname()
	}
	if hostname == "" {
		hostname = "localhost"
	}

	args := []string{"-hostname", hostname}
	values := [][2]string{
		{"certFile", "-certFile"}, {"keyFile", "-keyFile"},
		{"setEdition", "-setEdition"}, {"listenip", "-listenip"},
		{"listenport", "-listenport"}, {"sshport", "-sshport"},
		{"reverseProxyPort", "-reverseProxyPort"}, {"publicIP", "-publicIP"},
		{"publicHostname", "-publicHostname"}, {"bindInterface", "-bindInterface"},
		{"setLicenseKey", "-setLicenseKey"}, {"recoverAccount", "-recoverAccount"},
		{"setPass", "-setPass"},
	}
	args = append(args, "-db", db)
	for _, pair := range values {
		if value := os.Getenv(pair[0]); value != "" {
			args = append(args, pair[1], value)
		}
	}
	for _, pair := range [][2]string{{"reverseProxy", "-reverseProxy"}, {"debug", "-debug"}} {
		enabled, _, err := boolEnv(pair[0])
		if err != nil {
			fmt.Fprintln(os.Stderr, "invalid boolean", pair[0], err)
			os.Exit(2)
		}
		if enabled {
			args = append(args, pair[1])
		}
	}
	https, specified, err := boolEnv("https")
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid boolean https:", err)
		os.Exit(2)
	}
	if !specified {
		cert, key := os.Getenv("certFile"), os.Getenv("keyFile")
		if cert != "" && key != "" {
			_, certErr := os.Stat(cert)
			_, keyErr := os.Stat(key)
			https = certErr == nil && keyErr == nil
		}
	}
	if https {
		args = append(args, "-https")
	}
	verbose, _, err := boolEnv("verbose")
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid boolean verbose:", err)
		os.Exit(2)
	}
	shortVerbose, _, err := boolEnv("v")
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid boolean v:", err)
		os.Exit(2)
	}
	if verbose || shortVerbose {
		args = append(args, "-v")
	}

	// Additional native C2 arguments can be supplied directly after the image name.
	// This avoids shell-style parsing ambiguities and permits quoted values.
	args = append(args, os.Args[1:]...)
	fmt.Fprintln(os.Stderr, "Starting Hak5 Cloud C2")
	if err := syscall.Exec("/app/c2", append([]string{"/app/c2"}, args...), os.Environ()); err != nil {
		fmt.Fprintln(os.Stderr, "cannot start Hak5 Cloud C2:", err)
		os.Exit(1)
	}
}
