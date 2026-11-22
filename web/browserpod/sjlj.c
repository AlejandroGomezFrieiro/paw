// setjmp and longjmp for Lua in a BrowserPod pod. The pod's musl has no
// setjmp, so Lua is compiled with LLVM's lowering of setjmp and longjmp to
// WebAssembly exceptions (-mllvm -wasm-enable-sjlj, see build-paw.sh), and
// this file gives the three functions that the lowering calls, after
// wasi-libc's and emscripten's.
#include <stdint.h>

struct jmp_buf_impl {
  void *func_invocation_id;
  uint32_t label;
};

struct arg {
  void *env;
  int val;
};

static _Thread_local struct arg longjmp_arg;

void __wasm_setjmp(void *env, uint32_t label, void *func_invocation_id) {
  struct jmp_buf_impl *jb = env;
  jb->func_invocation_id = func_invocation_id;
  jb->label = label;
}

uint32_t __wasm_setjmp_test(void *env, void *func_invocation_id) {
  struct jmp_buf_impl *jb = env;
  if (jb->func_invocation_id == func_invocation_id) return jb->label;
  return 0;
}

void __wasm_longjmp(void *env, int val) {
  struct arg *a = &longjmp_arg;
  a->env = env;
  a->val = val != 0 ? val : 1;
  __builtin_wasm_throw(1, a);
}
