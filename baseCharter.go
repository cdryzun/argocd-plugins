package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"sigs.k8s.io/kustomize/api/filesys"
	"sigs.k8s.io/kustomize/api/krusty"
)

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func writeFile(filename, content string) {
	err := os.WriteFile(filename, []byte(content), 0644)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func removeFile(filename string) {
	if _, err := os.Stat(filename); err == nil {
		os.Remove(filename)
	}
}

func processConfigFiles() {
	if _, err := os.Stat("config"); !os.IsNotExist(err) {
		files, err := os.ReadDir("config")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

		for _, file := range files {
			fileName := filepath.Join("config", file.Name())
			configMapName := strings.ReplaceAll(file.Name(), ".", "-")

			kcmd := exec.Command("kustomize", "edit", "add", "configmap", configMapName, "--from-file", fileName)
			kcmd.Stdout = os.Stdout
			kcmd.Stderr = os.Stderr
			err := kcmd.Run()
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
		}
	}
}

func main() {
	// Obtain values from environment variables with default values
	chartHome := getEnv("CHART_HOME", "/tmp")
	appBaseName := getEnv("APP_BASE_NAME", "app-base")

	kustomizationContent := fmt.Sprintf(`helmGlobals:
  chartHome: %s
helmCharts:
- name:  %s
  valuesFile: values.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
`, chartHome, appBaseName)

	writeFile("kustomization.yaml", kustomizationContent)
	defer removeFile("kustomization.yaml")

	kustOptions := krusty.MakeDefaultOptions()
	kustOptions.PluginConfig.HelmConfig.Enabled = true
	kustOptions.PluginConfig.HelmConfig.Command = "helm"
	k := krusty.MakeKustomizer(kustOptions)
	fs := filesys.MakeFsOnDisk()
	processConfigFiles()

	t, err := k.Run(fs, ".")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	yamlBytes, err := t.AsYaml()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Print(string(yamlBytes))
}
