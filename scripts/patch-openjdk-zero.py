#!/usr/bin/env python3
"""Adapt the pinned OpenJDK bsd_zero port to its shared W^X bookkeeping API.

The state transitions follow OpenJDK's bsd_aarch64 implementation at the same
revision. iOS Zero keeps its existing no-pthread-JIT behavior. This changes
separately licensed OpenJDK sources, not the NovaCraft app's memory policy.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])
p = root / 'src/hotspot/os_cpu/bsd_zero/os_bsd_zero.cpp'
s = p.read_text()
old = '''#if defined(AARCH64) && defined(__APPLE__)
void os::current_thread_enable_wx(WXMode mode) {
#ifndef __IOS__
  pthread_jit_write_protect_np(mode == WXExec);
#endif
}
#endif'''
new = '''// NovaCraft compatibility patch: shared W^X API added after this Zero
// backend was written. State transitions match the sibling bsd_aarch64 port.
#if defined(AARCH64) && defined(__APPLE__)
WXMode DefaultWXWriteMode = WXWrite;
THREAD_LOCAL bool os::_jit_exec_enabled = false;

void os::current_thread_enable_wx(WXMode mode) {
  bool exec_enabled = mode != WXWrite;
  if (exec_enabled != _jit_exec_enabled NOT_PRODUCT( || DefaultWXWriteMode == WXWrite)) {
#ifndef __IOS__
    pthread_jit_write_protect_np(exec_enabled);
#endif
    _jit_exec_enabled = exec_enabled;
  }
}

bool Thread::wx_enable_write() {
  if (_wx_state == WXArmedForWrite) {
    _wx_state = WXWrite;
    os::current_thread_enable_wx(WXWrite);
    return true;
  }
  return false;
}

void os::thread_wx_enable_write_impl() {
  if (!StressWXHealing) {
    Thread::current()->wx_enable_write();
  }
}
#endif'''
if s.count(old) != 1:
    raise SystemExit('Pinned bsd_zero W^X block changed; review source before patching')
p.write_text(s.replace(old, new))
print('Updated bsd_zero W^X bookkeeping for the pinned shared runtime API')
