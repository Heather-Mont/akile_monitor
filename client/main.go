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
	"akile_monitor/client/model"
	"bytes"
	"compress/gzip"
	"flag"
	"github.com/cloudwego/hertz/pkg/common/json"
	"github.com/henrylee2cn/goutil/calendar/cron"
	"log"
	"os"
	"os/signal"
	"time"
	"github.com/gorilla/websocket"
	"golang.org/x/net/proxy"
)

func main() {
	LoadConfig()

	go func() {
		c := cron.New()
		c.AddFunc("* * * * * *", func() {
			TrackNetworkSpeed()
		})
		c.Start()
	}()

	flag.Parse()
	log.SetFlags(0)

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)

	// 配置 WebSocket 拨号器
	dialer := &websocket.Dialer{
		HandshakeTimeout: 10 * time.Second, // 添加超时控制
	}

	// 根据配置文件决定是否使用代理
	if cfg.Proxy.Enabled {
		log.Printf("Proxy enabled: %s (%s)", cfg.Proxy.Type, cfg.Proxy.Address)
		switch cfg.Proxy.Type {
		case "socks5":
			socks5Dialer, err := proxy.SOCKS5("tcp", cfg.Proxy.Address, nil, proxy.Direct)
			if err != nil {
				log.Fatal("SOCKS5 proxy setup failed:", err)
			}
			dialer.NetDial = socks5Dialer.Dial
		case "http":
			// 如果需要支持 HTTP 代理，可以在这里扩展
			log.Println("HTTP proxy not implemented yet")
			return
		default:
			log.Fatalf("Unsupported proxy type: %s", cfg.Proxy.Type)
		}
	} else {
		log.Println("No proxy configured, using direct connection")
	}

	u := cfg.Url
	log.Printf("connecting to %s", u)

	// 使用拨号器连接 WebSocket
	c, _, err := dialer.Dial(cfg.Url, nil)
	if err != nil {
		log.Fatal("dial:", err)
	}
	defer c.Close()

	c.WriteMessage(websocket.TextMessage, []byte(cfg.AuthSecret))

	done := make(chan struct{})

	_, message, err := c.ReadMessage()
	if err != nil {
		log.Println("auth_secret验证失败")
		log.Println("read:", err)
		return
	}
	if string(message) == "auth success" {
		log.Println("auth_secret验证成功")
		log.Println("正在上报数据...")
	}

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-done:
			return
		case t := <-ticker.C:
			var D struct {
				Host      *model.Host
				State     *model.HostState
				TimeStamp int64
			}
			D.Host = GetHost()
			D.State = GetState()
			D.TimeStamp = t.Unix()
			// gzip 压缩 json
			dataBytes, err := json.Marshal(D)
			if err != nil {
				log.Println("json.Marshal error:", err)
				return
			}

			var buf bytes.Buffer
			gz := gzip.NewWriter(&buf)
			if _, err := gz.Write(dataBytes); err != nil {
				log.Println("gzip.Write error:", err)
				return
			}

			if err := gz.Close(); err != nil {
				log.Println("gzip.Close error:", err)
				return
			}

			err = c.WriteMessage(websocket.TextMessage, buf.Bytes())
			if err != nil {
				log.Println("write:", err)
				return
			}
		case <-interrupt:
			log.Println("interrupt")
			err := c.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
			if err != nil {
				log.Println("write close:", err)
				return
			}
			select {
			case <-done:
			case <-time.After(time.Second):
			}
			return
		}
	}
}