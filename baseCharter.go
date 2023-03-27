package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
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
	err := ioutil.WriteFile(filename, []byte(content), 0644)
	if err != nil {
		panic(err)
	}
}

func removeFile(filename string) {
	if _, err := os.Stat(filename); err == nil {
		os.Remove(filename)
	}
}

func processConfigFiles() {
	if _, err := os.Stat("config"); !os.IsNotExist(err) {
		files, err := ioutil.ReadDir("config")
		if err != nil {
			panic(err)
		}

		for _, file := range files {
			fileName := filepath.Join("config", file.Name())
			configMapName := strings.ReplaceAll(file.Name(), ".", "-")

			kcmd := exec.Command("kustomize", "edit", "add", "configmap", configMapName, "--from-file", fileName)
			kcmd.Stdout = os.Stdout
			kcmd.Stderr = os.Stderr
			err := kcmd.Run()
			if err != nil {
				panic(err)
			}
		}
	}
}

func main() {
	result := []unstructured.Unstructured{}

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
	kustOptions := krusty.MakeDefaultOptions()
	kustOptions.PluginConfig.HelmConfig.Enabled = true
	kustOptions.PluginConfig.HelmConfig.Command = "helm"
	k := krusty.MakeKustomizer(kustOptions)
	fs := filesys.MakeFsOnDisk()
	processConfigFiles()

	defer func() {
		removeFile("kustomization.yaml")
		if r := recover(); r != nil {
			panic(r)
		}
	}()

	t, err := k.Run(fs, ".")
	if err != nil {
		panic(err)
	}
	for _, m := range t.Resources() {
		mm, err := m.Map()
		if err != nil {
			panic(err)
		}
		result = append(result, unstructured.Unstructured{
			Object: mm,
		})
	}
	yamlBytes, err := t.AsYaml()
	if err != nil {
		panic(err)
	}
	fmt.Print(string(yamlBytes))
}
