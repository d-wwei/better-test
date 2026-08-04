#!/usr/bin/env python3
"""Timeout fixture for the declared-provider runner."""

import time

time.sleep(5)
print('{"provider":{"id":"fixture.slow","version":"1.0.0"}}')
