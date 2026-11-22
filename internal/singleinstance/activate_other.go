//go:build !windows

package singleinstance

func grantExistingSingleInstanceForeground(pid int) {}

func ActivateExistingWindow(pid int) {}

func HideExistingWindow(pid int) {}

func HasExistingWindow(pid int) bool { return false }
