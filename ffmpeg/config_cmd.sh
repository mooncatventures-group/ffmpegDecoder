#!/bin/bash

./configure --enable-cross-compile --arch=arm --target-os=darwin --cc='/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/gcc -arch armv7 --verbose' --sysroot=/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS5.0.sdk --extra-ldflags=-L/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS5.0.sdk/usr/lib/system