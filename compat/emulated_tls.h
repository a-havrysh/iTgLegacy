// emulated_tls.h - pthread_key_t based thread-local storage for targets where
// the compiler/dyld does not support native TLS (armv7 iOS < 9.0).
//
// Real native TLS (`thread_local`/`__thread`) on Darwin's ARM32 backend is
// rejected by clang below -miphoneos-version-min=9.0, and even forcing the
// version does not help: it compiles to dyld TLV relocations that iOS 6-8's
// dyld cannot resolve. This header replaces each TD_THREAD_LOCAL variable
// with a pthread_key_t-backed accessor function instead, which needs nothing
// beyond pthread (available since iOS 2).
#pragma once

#include <pthread.h>
#include <new>

namespace td {
namespace detail {

// One instantiation per (T, Tag) pair gets its own pthread_key_t and its own
// per-thread heap block. Tag exists only to let multiple same-typed TLS
// variables in one translation unit get distinct keys.
template <class T, int Tag>
T &emulated_tls_ref() {
  static pthread_key_t key = [] {
    pthread_key_t k;
    pthread_key_create(&k, [](void *p) { delete static_cast<T *>(p); });
    return k;
  }();
  auto *p = static_cast<T *>(pthread_getspecific(key));
  if (p == nullptr) {
    p = new T();
    pthread_setspecific(key, p);
  }
  return *p;
}

}  // namespace detail
}  // namespace td

// For a function-local `static TD_THREAD_LOCAL Type name;`: replace with
//   TD_EMULATED_TLS_LOCAL(Type, name)
// which binds `name` as a real reference to the per-thread storage. No other
// line in the function needs to change.
#define TD_EMULATED_TLS_LOCAL(Type, Name) auto &Name = ::td::detail::emulated_tls_ref<Type, __COUNTER__>()

// For a class-static or file-static `TD_THREAD_LOCAL Type name;` referenced
// from other functions: replace the declaration with
//   TD_EMULATED_TLS_MEMBER(Type, name)
// which defines an accessor function `name()`; update every call site from
// `name` to `name()`.
#define TD_EMULATED_TLS_MEMBER(Type, Name) \
  static Type &Name() { return ::td::detail::emulated_tls_ref<Type, __COUNTER__>(); }
