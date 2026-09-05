#!/bin/sh
# 打包演示插件
cd "$(dirname "$0")"
zip -r -FS ../plugin.demo.guide.zip plugin.toml demo_guide.py pages
