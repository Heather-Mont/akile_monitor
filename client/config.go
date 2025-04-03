// Copyright 2023 Akile Network Authors
// Copyright 2025 Heather-Mont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"encoding/json"
	"log"
	"os"
)

type ProxyConfig struct {
	Enabled bool   `json:"enabled"` // 是否启用代理
	Type    string `json:"type"`    // 代理类型: "socks5" 或 "http"
	Address string `json:"address"` // 代理地址，例如 "127.0.0.1:40000"
}

type Config struct {
	AuthSecret string      `json:"auth_secret"`
	Url        string      `json:"url"`
	NetName    string      `json:"net_name"`
	Name       string      `json:"name"`
	DiskName   string      `json:"disk_name"` // 新增磁盘名称配置
	Proxy      ProxyConfig `json:"proxy"` // 代理配置
}

var cfg *Config

func LoadConfig() {
	file, err := os.ReadFile("client.json")
	if err != nil {
		log.Printf("Failed to read client.json: %v, using default config", err)
		cfg = &Config{} // 默认空配置
		return
	}
	cfg = &Config{}
	err = json.Unmarshal(file, cfg)
	if err != nil {
		log.Printf("Failed to parse client.json: %v, using default config", err)
		cfg = &Config{} // 默认空配置
		return
	}
	log.Println("Config loaded successfully")
}
