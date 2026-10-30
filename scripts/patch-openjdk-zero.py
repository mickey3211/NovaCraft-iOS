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

# NativeLibraries.c recognizes built-ins through JNI_OnLoad_<library> and
# bypasses JVM_LoadLibrary for those. External LWJGL JNI libraries must receive
# their own dlopen handle, even when libjvm itself is statically linked. Apple's
# default process handle uses RTLD_FIRST and cannot resolve these libraries.
p = root / 'src/hotspot/os/bsd/os_bsd.cpp'
s = p.read_text()
old = '''#ifdef __APPLE__
void * os::dll_load(const char *filename, char *ebuf, int ebuflen) {
  if (is_vm_statically_linked()) {
    return os::get_default_process_handle();
  }

  log_info(os)("attempting shared library load of %s", filename);'''
new = '''#ifdef __APPLE__
void * os::dll_load(const char *filename, char *ebuf, int ebuflen) {
#ifndef __IOS__
  if (is_vm_statically_linked()) {
    return os::get_default_process_handle();
  }
#endif
  // NovaCraft iOS: built-in JNI libraries are resolved by NativeLibraries.c.
  // External signed app libraries need their real handle and JNI_OnLoad.
  // Keep dlopen errors intact; never report the process as a missing library.
  log_info(os)("attempting shared library load of %s", filename);'''
if s.count(old) != 1:
    raise SystemExit('Pinned Apple dll_load block changed; review before patching')
p.write_text(s.replace(old, new))
print('Enabled real external JNI library handles for statically linked iOS Zero')
