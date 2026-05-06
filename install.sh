#!/bin/sh

git apply statusline.patch
mkdir -p ~/.config/micro/colorschemes
cp micro-powerline.micro ~/.config/micro/colorschemes/
mkdir -p ~/.config/micro/plug/micro-powerline
cp micro-powerline.lua ~/.config/micro/plug/micro-powerline/
